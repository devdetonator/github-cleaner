#!/bin/bash

platform='unknown'
unamestr=`uname`
if [[ "$unamestr" == 'Linux' ]]; then
   platform='linux'
elif [[ "$unamestr" == 'Darwin' ]]; then
   platform='bsd'
fi

function usage() {
	echo "Usage:"
	echo -n "github-cleaner -t [oauth api token] -o [github repo owner] -r [github repo] --days [n]"
	echo " - deletes branches older than [n] days since today"
	echo -n "github-cleaner -t [oauth api token] -o [github repo owner] -r [github repo] --date [YYYY-MM-DD]"
	echo " - delets branches older than date specified"
	exit 1
}

function get_days_to_skip_iso8601() {
	if [[ $platform == 'linux' ]]; then
		date -u --date="-${1} days" +"%Y-%m-%dT%H:%M:%SZ"
	elif [[ $platform == 'bsd' ]]; then
		date -j -v-${1}d +"%Y-%m-%dT%H:%M:%SZ"
	fi
	if [ $? -ne 0 ]; then
		echo "$0" " error: days to skip must be a number!"
		exit 1
	fi
}

function get_date_in_iso8601() {
	if [[ $platform == 'linux' ]]; then
		date -u --date="$1" +"%Y-%m-%dT%H:%M:%SZ"
	elif [[ $platform == 'bsd' ]]; then
		date -j -f"%Y-%m-%d" "$1" +"%Y-%m-%dT%H:%M:%SZ"
	fi
	if [ $? -ne 0 ]; then
		echo "$0" " error: bad date format " "$1"
		exit 1
	fi
}

function get_utc_date_from_iso8601() {
	if [[ $platform == 'linux' ]]; then
		date -u --date="$1" +"%Y-%m-%d %H:%M:%S"
	elif [[ $platform == 'bsd' ]]; then
		date -u -j -f"%Y-%m-%dT%H:%M:%SZ" "$1" +"%Y-%m-%d %H:%M:%S"	
	fi
	if [ $? -ne 0 ]; then
		echo "$0" " exception: unable to convert " "$1" " to iso8601 format!"
		exit 1
	fi
}

function github_check_rate() {
	rate_remaining=`curl -H "Authorization: token ${GITHUB_TOKEN}" -Ss https://api.github.com/rate_limit | jq ".rate.remaining"`
	if [ $rate_remaining -lt 60 ]; then
		echo `basename $0` ": rate limit is less than 60, please use another OAuth token!"
		exit 1
	fi 
}

function github_is_branch_old() {
    commit=$1
    modified_since_utc=$2
    commiter_date=$(curl -H "Authorization: token ${GITHUB_TOKEN}" -sS -X GET https://api.github.com/repos/$OWNER/$REPO/git/commits/${commit} | jq --raw-output '.committer.date')
    commit_date_utc=$(get_utc_date_from_iso8601 "$commiter_date")

    if [[ $commit_date_utc < $modified_since_utc ]]; then
    	return 1
    fi

    return 0
}

function github_delete_branch() {
	local branch=$1
	echo -n "Deleting $branch"
	status=$(curl --write-out %{http_code} --output /dev/null -H "Authorization: token ${GITHUB_TOKEN}" -sS -X DELETE https://api.github.com/repos/$OWNER/$REPO/git/$branch)
	if [ ${status} -eq 204 ];then
		echo "..ok"
	else
		echo "..HTTP error " "${status}" "! Please check permissions!"
	fi 
}

function github_remove_branches_before() {
    date_before_in_utc=$(get_utc_date_from_iso8601 "$1")
    tmp_refs=`mktemp`
    tmp_filtered=`mktemp`

	curl -H "Authorization: token ${GITHUB_TOKEN}" -sS https://api.github.com/repos/{$OWNER}/${REPO}/git/refs/heads -o $tmp_refs
	
	if [[ -s "$tmp_refs" ]]; then
		echo -n
	else 
		echo "$0" "error: couldn't accessing ref list from GitHub API, check your OAuth token!"
		exit 1
	fi

	cat $tmp_refs | jq '[.[] | select (.ref != "refs/heads/master")]' \
	    | jq  --raw-output '.[] | select(.object.type == "commit") as $x | $x.ref, $x.object.sha' > $tmp_filtered
    
	if [[ -s "$tmp_filtered" ]]; then
		echo -n
	else 
		master_data=$(cat $tmp_refs | jq --raw-output '[.[] | select (.ref == "refs/heads/master")]')
		if [[ -z ${master_data} ]]; then
			echo "$0" "error: something wrong with Jq presence or GitHub API output, please check it!"
			exit 1
		fi
		#echo "$0" "no branches beeting date requirements left. Bye"
		exit 0
	fi

	while read -r branch; read -r commit; do
		github_is_branch_old "$commit" "$date_before_in_utc"
	  	if [[ $? -eq 1 ]]; then
			github_delete_branch "$branch"	  	
	  	fi
	done < $tmp_filtered
	exit 0
}

if [[ $# -lt 8 ]]; then
	echo "$0" "error: all options must be specified!"
	usage
	exit 1
fi 

while [[ $# -gt 1 ]]
do
		key="$1"
		case $key in
		    -t|--token)
		    GITHUB_TOKEN="$2"
		    if [ -z "${GITHUB_TOKEN// }" ]; then
		    	echo "$0" "error: GitHub OAuth token is a required parameter!"	
		     	usage
		     	exit 1
		    fi
		    shift # past argument
		    ;;
		    -r|--repository)
		    REPO="$2"
		    if [ -z "${REPO// }" ]; then
		    	echo "$0" "error: GitHub repository is a required parameter!"	
		    	usage
		     	exit 1
		    fi
		    shift # past argument
		    ;;
		    -o|--owner)
		    OWNER="$2"
		    if [ -z "${OWNER// }" ]; then
		    	echo "$0" "error: GitHub repo owner is a required parameter!"	
		     	usage
		     	exit 1
		    fi
		    shift # past argument
		    ;;
		    --days)
		    DAYS_TO_SKIP="$2"
		    shift # past argument
		    ;;
		    --date)
		    BEFORE_DATE="$2"
		    shift # past argument
		    ;;
		    *)
		      usage
		    ;;
		esac
	shift # past argument or value
done

if [ -z "${BEFORE_DATE// }" ]; then
	if [ -z "${DAYS_TO_SKIP// }" ]; then
		echo "$0" "error: at least --days or --date must be set!"	
		usage
	fi 
	date_before=$(get_days_to_skip_iso8601 "$DAYS_TO_SKIP")
else
	if [ -n "${DAYS_TO_SKIP// }" ]; then
		echo "$0" "error: please don't use both --days and --date parameters!"	
		usage
	fi
	date_before=$(get_date_in_iso8601 "$BEFORE_DATE")
fi

github_check_rate
github_remove_branches_before "$date_before"






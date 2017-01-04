
# A GitHub repo cleaning script

## Requirements

* A Linux or OS X environment
* Bash shell
* curl (tested against 7.51.0)
* jq <http://stedolan.github.io/jq/> (tested against 1.5)
  If jq is not installed commands will output raw JSON; if jq is installed
  the output will be formatted and filtered for use with other shell tools.

## Setup
* Be sure, you've installed all the required components to sucessfully run the script.

* [Generate GitHub OAuth token](https://help.github.com/articles/creating-an-access-token-for-command-line-use/) which is required to run script (allows rate limit 5000 instead of 60).

## Usage

Delete branches older than [n] days since today:

`github-cleaner -t [oauth api token] -o [github repo owner] -r [github repo] --days [n]`

Delete branches older than some date:

`github-cleaner -t [oauth api token] -o [github repo owner] -r [github repo] --date [YYYY-MM-DD]`

Parameter | Description
---- | -----------
-t   | GitHub OAuth token
-o   | GitHub repository owner
-r   | GitHub repository
--date | `YYYY-MM-DD` format. Branches that were last modified before this date will be removed. 
--days | alternate way set removal of branches that are N days older since now. 


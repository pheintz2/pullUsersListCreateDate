#!/bin/bash

# Configuration variables
ORGANIZATION="banno"
GITHUB_TOKEN="YOUR_TOKEN_HERE" # Personal Access Token with repo scope
OUTPUT_FILE="repos_and_branches_report.txt"
TEMP_DIR="temp_repo_data"

TEMP_DIR="/tmp/temp_repo_data" # Specify an absolute path for the temporary directory
PAGE_SIZE=100 # GitHub's maximum page size is 100
DELAY=1 # Delay in seconds between requests to avoid hitting the rate limit

# Create temporary directory if it doesn't exist
if ! mkdir -p "$TEMP_DIR"; then
    echo "Error: Unable to create temporary directory $TEMP_DIR"
    exit 1
fi

# Function to get all repositories from the organization
get_repos() {
    local page=1
    local total_pages=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/$ORGANIZATION/repos?per_page=$PAGE_SIZE&page=$page" | jq -r '. | length // 1')
    
    while [ $page -le $total_pages ]; do
        curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/orgs/$ORGANIZATION/repos?per_page=$PAGE_SIZE&page=$page" |
        jq -r '.[] | [.ssh_url, .created_at, .owner.login, .default_branch] | @tsv' >> "$TEMP_DIR/repos.txt"
        
        page=$((page + 1))
        sleep $DELAY
    done
}

# Function to get branches for each repository
get_branches() {
    while IFS=$'\t' read -r repo created_at user default_branch; do
        # Extract the repository name from the SSH URL
        repo_name=$(echo "$repo" | cut -d '/' -f 4)
        echo "Fetching branches for $repo_name"
        
        # Debug: Print the repository URL
        echo "Repository URL: $repo"
        
        # Get the branches for the repository
        branches=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$ORGANIZATION/$repo_name/branches")
        
        # Debug: Print the branches JSON response
        echo "Branches JSON Response:"
        echo "$branches"
        
        # Check if the response is an error
        if echo "$branches" | jq -e > /dev/null 2>&1; then
            # Parse the branches JSON response
            echo "$branches" | jq -r '.[] | [.name, .commit.committer.date, .commit.committer.name] | @tsv' >> "$OUTPUT_FILE"
        else
            echo "Error fetching branches for $repo_name"
            echo "$branches" >> "$OUTPUT_FILE"
        fi
        
        # Add the default branch if it's not already in the list
        if ! grep -q "^$default_branch" "$OUTPUT_FILE"; then
            echo -e "$default_branch\tDefault branch\tDefault branch" >> "$OUTPUT_FILE"
        fi
        
        echo >> "$OUTPUT_FILE" # Add a newline between repositories
        sleep $DELAY
    done < "$TEMP_DIR/repos.txt"
}

# Main script execution
get_repos
get_branches

# Display the results
echo "Repository and branch report has been written to $OUTPUT_FILE"

# Cleanup
rm -rf "$TEMP_DIR"

# Exit the script
exit 0

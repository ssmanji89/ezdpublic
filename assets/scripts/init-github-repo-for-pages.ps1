$repoName = "IT-MSP-Resource"

# Create the repository directory
New-Item -ItemType Directory -Force -Path $repoName

# Change to the repository directory
Set-Location $repoName

# Initialize git
git init

# Create the directory structure
$directories = @(
    "posts",
    "resources"
)

foreach ($dir in $directories) {
    New-Item -ItemType Directory -Force -Path $dir
}

# Create index.md files in each directory
foreach ($dir in $directories) {
    $indexFile = Join-Path $dir "index.md"
    $content = @"
# $dir

Welcome to the $dir section of the IT MSP Resource public repository!

Please feel free to contribute by submitting pull requests or raising issues for discussion.
"@
    Set-Content -Path $indexFile -Value $content
}

# Add all files to git
git add .

# Commit the initial structure
git commit -m "Initialized index.md files"

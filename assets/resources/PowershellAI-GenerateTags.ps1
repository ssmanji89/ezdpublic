Install-Module -Name PowerShellAI

# Define the path to the PS1 files
$path = "C:\Users\ssman\OneDrive\Documents\GitHub\ezdpublic\assets\resources"

$ps1Files = Get-ChildItem -Path $path -Filter *.ps1 -Recurse
# Define the output file path for the Markdown file
$outputFilePath = ($path+"\index_ChatGPT.md")

# Define the regex pattern for comments
$commentPattern = "#\s*(.+)$"

# Set up ChatGPT API credentials
$apiKey = "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"
$baseUrl = "https://api.openai.com/v1"

# Get all PS1 files in the specified path

# Loop through each PS1 file and extract summaries and tags
$markdownContent = ""
foreach ($file in $ps1Files) {
    $fileContent = Get-Content $file.FullName; $fileContent.Replace('\r\n','   ')
    #$fileContent=    gc (($path)+"\Get-FilesOver1000MB.ps1") -Raw
    $dataBack = (gpt -temperature '.55' -max_tokens 2048 -Raw -Verbose -prompt "Generate a set of Tags using ChatGPT for a provided. "+$fileContent+"").choices.text
    $markdownContent += "## $($file.Name)`n"
    $markdownContent += "Tags: $($dataBack -join ", ")`n`n"
}

# Write the Markdown content to the output file
$markdownContent | Out-File $outputFilePath


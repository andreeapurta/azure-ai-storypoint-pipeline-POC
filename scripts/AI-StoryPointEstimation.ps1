param(
    [Parameter(Mandatory=$true)]
    [string]$Organization,
    
    [Parameter(Mandatory=$true)]
    [string]$Project,
    
    [Parameter(Mandatory=$true)]
    [string]$AccessToken,
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "requirement-estimation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Groq', 'Ollama')]
    [string]$AIProvider = 'Ollama',
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaEndpoint = 'http://localhost:11434',
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaModel = 'llama3.2:3b',
    
    [Parameter(Mandatory=$false)]
        # IMPORTANT: Set your Groq API key here or pass as a parameter. Example: 'sk-xxxxxxx'
        [string]$GroqApiKey = 'GROQ_API_KEY_PLACEHOLDER',
    
    [Parameter(Mandatory=$false)]
    [string]$GroqModel = 'llama-3.1-8b-instant',
    
    [Parameter(Mandatory=$false)]
    [string]$Sprint = 'Sprint 2'  # Optional: specify sprint manually (e.g., "Sprint 2")
)

# ...existing code...
# Replace any hardcoded org/project/token with placeholders
# Example:
# $org = $Organization.TrimEnd('/')
# $projectEncoded = [System.Uri]::EscapeDataString($Project)
# ...existing code...

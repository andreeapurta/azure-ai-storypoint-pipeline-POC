function Get-FreeAIEstimate {
    param([string]$Title, [string]$Description, [string]$WorkItemType, [string]$Team, [string]$Provider)
    Write-Log "PIPELINE DEBUG: Get-FreeAIEstimate called with Provider='$Provider', Team='$Team', Title='$Title'"
    
    # Count total words for logging/debugging
    $content = "$Title $Description"
    $wordCount = ($content -split '\s+').Count
    # Clean the title - remove all quote marks and special characters that might cause JSON issues
    $cleanTitle = $Title -replace '["\u0022\u201C\u201D\u2018\u2019]', "'" -replace '[\r\n\t]', ' ' -replace '[^\x20-\x7E ]', ' '
    $cleanTitle = $cleanTitle.Trim()
    
    # Clean the description - remove HTML tags, all quote marks, and special characters
    # Strip HTML tags before saving or matching
    $cleanDescription = $Description -replace '<[^>]+>', ' ' -replace '&nbsp;', ' ' -replace '&[a-z]+;', ' ' -replace '["\u0022\u201C\u201D\u2018\u2019]', "'" -replace '[^\x20-\x7E\n\r\t]', ' '
    $cleanDescription = $cleanDescription.Trim()
    if ($cleanDescription.Length -gt 2000) {
        $cleanDescription = $cleanDescription.Substring(0, 2000) + "..."
    }
    # Get similar historical stories for context (for better AI calibration)
    $historicalStories = Get-SimilarHistoricalStories -Title $Title -Description $cleanDescription -Team $Team
    
    # Build historical context section for prompt (shows AI relevant past stories)
    $historicalContext = ""
    if ($historicalStories.Count -gt 0) {
        $historicalContext = "`n`nHISTORICAL EXAMPLES (for reference):"
        foreach ($story in $historicalStories) {
            # Clean historical story data - replace all quotes with apostrophes
            $storyTitle = ($story.title -replace '["\u0022\u201C\u201D\u2018\u2019]', "'" -replace '[\r\n\t]', ' ').Trim()
            $storyDesc = ($story.description -replace '<[^>]+>', ' ' -replace '["\u0022\u201C\u201D\u2018\u2019]', "'" -replace '[\r\n\t]', ' ').Trim()
            if ($storyDesc.Length -gt 150) { $storyDesc = $storyDesc.Substring(0, 150) + "..." }
            $historicalContext += "`n- [$($story.estimated_sp) SP] $storyTitle (Team: $($story.team)) - $storyDesc"
        }
        $historicalContext += "`n`nUse these examples to calibrate your estimate, but base your decision on the current task's unique requirements."
    }
    # Build the AI prompt for story point estimation, acceptance criteria, and quality analysis
    $prompt = @"
Estimate story points for this software development task using Fibonacci sequence, generate acceptance criteria, and analyze description quality.

Task Title: $cleanTitle
Task Description: $cleanDescription
Team: $Team$historicalContext

Story Point Scale (Fibonacci):

Tasks:
1. Estimate story points based on complexity, uncertainty, and effort
2. Generate 2-4 clear, testable acceptance criteria
3. Analyze DESCRIPTION quality (ignore the title - only evaluate the description field):
   - needsClarification: true if the DESCRIPTION is empty, missing, too vague (less than 50 characters), or lacks implementation details
   - needsBreakdown: true if the DESCRIPTION shows the task is too complex, has multiple features, or should be split into smaller stories

CRITICAL: For needsClarification, ONLY look at the description field. If description is empty or very short, set needsClarification=true even if the title is clear.

Respond with ONLY valid JSON in this exact format. DO NOT include any explanation, markdown, or formatting before or after the JSON. Output ONLY the JSON object:
{"storyPoints": <number>, "confidence": "<High/Medium/Low>", "reasoning": "<brief explanation>", "acceptanceCriteria": ["Given X when Y then Z", "Given A when B then C", "..."], "needsClarification": <true/false>, "needsBreakdown": <true/false>}
"@
    try {
        # Select AI provider (Ollama = local, Groq = cloud)
        if ($Provider -eq 'Ollama') {
            # Local Ollama
            Write-Log "PIPELINE DEBUG: Using LOCAL Ollama at $OllamaEndpoint with model $OllamaModel"
            $apiEndpoint = "$OllamaEndpoint/v1/chat/completions"
            $modelName = $OllamaModel
            $apiKey = "" # No API key needed for local Ollama
        } else {
            # Groq Cloud AI (no local installation needed)
            Write-Log "PIPELINE DEBUG: Using CLOUD Groq API with model $GroqModel"
            $apiEndpoint = "https://api.groq.com/openai/v1/chat/completions"
            $modelName = $GroqModel
            $apiKey = $GroqApiKey
        }
        # Build request body for AI API
        $requestBody = @{
            model = $modelName
            messages = @(
                @{
                    role = "user"
                    content = $prompt
                }
            )
            temperature = 0.1
            max_tokens = 300
        } | ConvertTo-Json -Depth 4 -Compress
        Write-Log "PIPELINE DEBUG: Request body length: $($requestBody.Length) bytes"

        # Build HTTP headers based on provider
        if ($Provider -eq 'Ollama') {
            $headers = @{
                'Content-Type' = 'application/json'
            }
        } else {
            $headers = @{
                'Authorization' = "Bearer $apiKey"
                'Content-Type' = 'application/json'
            }
        }
        # Set timeout based on provider (Ollama needs more time for local processing)
        $timeoutSec = if ($Provider -eq 'Ollama') { 120 } else { 30 }
        try {
            # Call the AI API endpoint
            $response = Invoke-RestMethod -Uri $apiEndpoint -Method POST -Headers $headers -Body $requestBody -TimeoutSec $timeoutSec
        }
        catch {
            Write-Log "PIPELINE ERROR: $Provider API call failed" "ERROR"
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                Write-Log "PIPELINE ERROR: Status: $($_.Exception.Response.StatusCode.value__)" "ERROR"
            }
            throw $_.Exception
        }
        Write-Log "PIPELINE DEBUG: $Provider responded successfully"
        # Parse AI response (extract JSON from possible mixed/plain text)
        $aiContent = $response.choices[0].message.content
        Write-Log "PIPELINE DEBUG: Full AI response: $aiContent"
        # Save raw response for debugging
        $rawResponseFile = Join-Path (Split-Path -Parent $PSScriptRoot) "debug_ai_raw_response.txt"
        $aiContent | Out-File -FilePath $rawResponseFile -Encoding UTF8
        Write-Log "PIPELINE DEBUG: Saved raw AI response to $rawResponseFile"
        # Attempt to extract JSON from mixed/plain text (AI may return markdown or extra text)
        $jsonPattern = '{[\s\S]*?"storyPoints"[\s\S]*?}'
        $jsonMatch = $null
        if ($aiContent -match $jsonPattern) {
            $jsonMatch = $matches[0]
        } else {
            # Try cleaning up markdown/code block wrappers
            $cleanContent = $aiContent -replace '```json', '' -replace '```', '' -replace '\n', ' ' -replace '\r', ' '
            if ($cleanContent -match $jsonPattern) {
                $jsonMatch = $matches[0]
            }
        }
        if ($jsonMatch) {
            Write-Log "PIPELINE DEBUG: Extracted JSON: $jsonMatch"
            try {
                $aiResult = $jsonMatch | ConvertFrom-Json
                # Validate the response - Fibonacci scale including 0.5, max 8
                if ($aiResult.storyPoints -and $aiResult.storyPoints -in @(0.5,1,2,3,5,8)) {
                    $aiModelName = if ($Provider -eq 'Ollama') { "Ollama ($OllamaModel)" } else { "Groq Llama-3.1-8B (Cloud)" }
                    return @{
                        StoryPoints = $aiResult.storyPoints
                        Confidence = if ($aiResult.confidence) { $aiResult.confidence } else { "Medium" }
                        Reasoning = if ($aiResult.reasoning) { $aiResult.reasoning } else { "AI analysis completed" }
                        AcceptanceCriteria = if ($aiResult.acceptanceCriteria) { $aiResult.acceptanceCriteria } else { @() }
                        NeedsClarification = if ($null -ne $aiResult.needsClarification) { $aiResult.needsClarification } else { $false }
                        NeedsBreakdown = if ($null -ne $aiResult.needsBreakdown) { $aiResult.needsBreakdown } else { $false }
                        AIModel = $aiModelName
                        WordCount = $wordCount
                        RawResponse = $aiContent
                    }
                } else {
                    throw "Invalid story points value: $($aiResult.storyPoints)"
                }
            } catch {
                Write-Log "PIPELINE ERROR: JSON parsing failed: $($_.Exception.Message)" "ERROR"
                throw "Failed to parse AI JSON response"
            }
        } else {
            # If no valid JSON found, fail with error
            Write-Log "PIPELINE ERROR: No valid JSON found in AI response" "ERROR"
            throw "No valid JSON found in AI response"
        }
    }
    catch {
        Write-Log "CRITICAL: Groq AI estimation failed: $($_.Exception.Message)" "ERROR"
        Write-Log "Title: $Title" "ERROR"
        throw "AI estimation failed: $($_.Exception.Message)"
    }
}

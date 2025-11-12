function Get-SimilarHistoricalStories {
    param([string]$Title, [string]$Description, [string]$Team)
    # Database in repository root (two levels up from scripts/functions)
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $dbPath = Join-Path $repoRoot "estimation-memory.db"
    Write-Log "DEBUG: Looking for estimation-memory.db at: $dbPath" "INFO"
    if (-not (Test-Path $dbPath)) {
        Write-Log "ERROR: estimation-memory.db not found at $dbPath - estimating without memory" -Level "ERROR"
        return @()
    }
    try {
    # Extract top 10 keywords from title and description (cleaned, significant words only)
    # Strip HTML tags from title and description for keyword extraction
    $plainTitle = $Title -replace '<[^>]+>', ' '
    $plainDescription = $Description -replace '<[^>]+>', ' '
    $combinedText = ($plainTitle + " " + $plainDescription) -replace '[^\w\s]', ' '
        $rawKeywords = $combinedText -split '\s+' | Where-Object { $_.Length -gt 3 }
        # Synonym expansion using Datamuse API (public, only sends keywords)
        $keywords = @()
        $genericWords = @('it','this','that','which','who','whom','both','them','children','enemy','side','end','get','have','take','assume','prepare','produce','apply','customer','enjoyer','exploiter','substance','abuser','drug','post','word','parole','passcode','tokenish','vetting','acquire','originate','back','rear','trailing','culmination','metric','parameter','hallmark','assay-mark','authentification','tokenish','netmail','electronic','mail','e-mail','returns','come','back','go','comeback','bring','affirms','ascertains','attest','corroborate','formalize','consent','admit','username','sign-on','logon','log','log in','log on','sign-on','audited account','examination','scrutinize','inspect','review','monitor','track','activity','certificate','certification','delegation','accreditation','jurisdiction','email','url','password','watchword','validate','corroborate','formalize','affirms','ascertains','attest','them','elles','ces')
        foreach ($word in $rawKeywords) {
            $keywords += $word.ToLower()
            try {
                $apiUrl = "https://api.datamuse.com/words?ml=$($word.ToLower())&max=5"
                $response = Invoke-RestMethod -Uri $apiUrl -Method GET -ErrorAction SilentlyContinue
                if ($response) {
                    $synonyms = $response | Select-Object -ExpandProperty word | Where-Object { $_.Length -gt 3 -and $genericWords -notcontains $_.ToLower() }
                    $keywords += $synonyms | Select-Object -First 2
                }
            } catch {
                Write-Log "Datamuse API failed for '$word': $($_.Exception.Message)" -Level "WARN"
            }
        }
        $keywords = $keywords | Select-Object -Unique

        if ($keywords.Count -eq 0) {
            Write-Log "No keywords extracted - using fallback query" -Level "WARN"
            $fallbackQuery = "SELECT work_item_id, title, description, estimated_sp, actual_sp, team, iteration_path 
                              FROM estimations 
                              ORDER BY work_item_id DESC 
                              LIMIT 5"
            return Invoke-SqliteQuery -DataSource $dbPath -Query $fallbackQuery -ErrorAction SilentlyContinue
        }

        Write-Log "Extracted keywords for similarity search (with synonyms): $($keywords -join ', ')"

        # Build SQL LIKE conditions for fuzzy/partial matching
        $keywordConditions = $keywords | ForEach-Object { 
            $escapedKeyword = $_ -replace "'", "''"
            "(LOWER(title) LIKE '%$($escapedKeyword)%' OR LOWER(description) LIKE '%$($escapedKeyword)%')" 
        }
            $whereClause = ($keywords | ForEach-Object { "title LIKE '%$_%' OR description LIKE '%$_%'" }) -join ' OR '
        Write-Log "SQL WHERE clause for similarity: $whereClause"

        # Query ALL historical stories that match ANY keyword
        $query = "SELECT work_item_id, title, description, estimated_sp, actual_sp, team, iteration_path 
                  FROM estimations 
                  WHERE $whereClause"
        Write-Log "Executing similarity query: $query"

        $allMatches = Invoke-SqliteQuery -DataSource $dbPath -Query $query -ErrorAction SilentlyContinue
        Write-Log "Raw candidate stories found: $($allMatches.Count)"
        if ($allMatches -and $allMatches.Count -gt 0) {
            foreach ($story in $allMatches) {
                $storyText = ($story.title + " " + $story.description).ToLower()
                $matchedKeywords = $keywords | Where-Object { $storyText -like "*$_*" }
                if ($matchedKeywords.Count -ge 3) {
                    $descPreview = if ($story.description.Length -gt 80) { $story.description.Substring(0,80) + "..." } else { $story.description }
                    Write-Log "RAW CANDIDATE: #$($story.work_item_id) [$($story.team)] $($story.title) | Desc: $descPreview | Matched keywords: $($matchedKeywords -join ', ')" "INFO"
                }
            }
        }
        if (-not $allMatches -or $allMatches.Count -eq 0) {
            Write-Log "No keyword matches found - using recent stories fallback" -Level "WARN"
            $fallbackQuery = "SELECT work_item_id, title, description, estimated_sp, actual_sp, team, iteration_path 
                              FROM estimations 
                              WHERE team = '$Team'
                              ORDER BY work_item_id DESC 
                              LIMIT 5"
            return Invoke-SqliteQuery -DataSource $dbPath -Query $fallbackQuery -ErrorAction SilentlyContinue
        }

        Write-Log "Found $($allMatches.Count) stories matching keywords - scoring for relevance..."

        # Score each match based on: overlap ratio + team match + SP similarity
        $scoredResults = @()
        foreach ($story in $allMatches) {
            $score = 0
            $storyText = ($story.title + " " + $story.description).ToLower()
            $matchedKeywords = $keywords | Where-Object { $storyText -like "*$($_)*" }
            $overlapRatio = if ($keywords.Count -gt 0) { [math]::Round($matchedKeywords.Count / $keywords.Count,2) } else { 0 }
            $score += [int]($overlapRatio * 10) # up to 10 points for overlap

            # Team match bonus (5 points if same team)
            if ($story.team -eq $Team) {
                $score += 5
            }

            # Story point similarity bonus (2 points if SP is a Fibonacci value)
            $spValue = [int]$story.estimated_sp
            if ($spValue -in @(1,2,3,5,8)) {
                $score += 2
            }

            $scoredResults += [PSCustomObject]@{
                work_item_id = $story.work_item_id
                title = $story.title
                description = $story.description
                estimated_sp = $story.estimated_sp
                actual_sp = $story.actual_sp
                team = $story.team
                iteration_path = $story.iteration_path
                relevance_score = $score
                overlap_ratio = $overlapRatio
                matched_keywords = $matchedKeywords -join ', '
            }
        }

        # Return top 5 most relevant stories
        $topResults = $scoredResults | Sort-Object relevance_score -Descending | Select-Object -First 5

        Write-Log "Top 5 most relevant stories (scores: $($topResults.relevance_score -join ', '), overlap ratios: $($topResults.overlap_ratio -join ', '))"
        foreach ($result in $topResults) {
            Write-Log "  - [Score: $($result.relevance_score)] [Overlap: $($result.overlap_ratio)] #$($result.work_item_id) - $($result.estimated_sp) SP - [$($result.team)] $($result.title.Substring(0, [Math]::Min(50, $result.title.Length)))... Keywords: $($result.matched_keywords)"
        }

        return $topResults
        
    } catch {
        Write-Log "Error querying historical data: $_" -Level "WARN"
        return @()
    }
}

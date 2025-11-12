# Initialize SQLite database for AI estimation memory
param(
    [Parameter(Mandatory=$false)]
    [string]$DbPath = "estimation-memory.db"
)

Write-Host "Initializing AI Estimation Memory Database..." -ForegroundColor Cyan

# Import PSSQLite module
Import-Module PSSQLite -ErrorAction Stop

# Create database file path in the repository root (parent of scripts folder)
$repoRoot = Split-Path -Parent $PSScriptRoot
$dbFullPath = Join-Path $repoRoot $DbPath

# Create tables using Invoke-SqliteQuery
Write-Host "Creating tables..." -ForegroundColor Yellow

# Estimation History - stores all closed User Stories with AI estimates
$createEstimationsTable = @"
CREATE TABLE IF NOT EXISTS estimations (
    work_item_id INTEGER PRIMARY KEY,
    work_item_type TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    team TEXT,
    ai_estimated_sp REAL,
    estimated_sp REAL NOT NULL,
    ai_confidence TEXT,
    ai_reasoning TEXT,
    ai_model TEXT,
    estimation_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_date DATETIME,
    iteration_path TEXT,
    area_path TEXT,
    tags TEXT,
    accuracy_score REAL
);
"@

# Execute table creation
Write-Host "  Creating estimations table..." -ForegroundColor Gray
Invoke-SqliteQuery -DataSource $dbFullPath -Query $createEstimationsTable

# Create indexes for performance
Write-Host "Creating indexes..." -ForegroundColor Yellow

$indexes = @(
    "CREATE INDEX IF NOT EXISTS idx_estimations_completed_date ON estimations(completed_date);",
    "CREATE INDEX IF NOT EXISTS idx_estimations_team ON estimations(team);",
    "CREATE INDEX IF NOT EXISTS idx_estimations_title ON estimations(title);",
    "CREATE INDEX IF NOT EXISTS idx_estimations_description ON estimations(description);"
)

foreach ($index in $indexes) {
    Invoke-SqliteQuery -DataSource $dbFullPath -Query $index
}

Write-Host "✅ Database initialized successfully!" -ForegroundColor Green
Write-Host "   Location: $dbFullPath" -ForegroundColor Cyan
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run Collect-HistoricalData.ps1 to populate with closed User Stories"
Write-Host "  2. AI will use this memory for better estimations"

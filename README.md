# AI Story Point Estimation Pipeline - Setup Instructions

This project provides the following automated functionalities:

- **Collect historical User Story data**
  - Gathers closed User Stories with story points from Azure DevOps.
  - Stores results in a local SQLite database for AI learning.
  - Pipeline: `azure-pipelines-learning.yml`
  - Script: `scripts/Collect-HistoricalData.ps1`

- **Estimate story points using AI (Ollama or Groq)**
  - Uses local Ollama or Groq cloud API to estimate story points for new User Stories.
  - Supports both private/local and cloud-based AI providers.
  - Pipeline: `azure-pipelines-learning.yml`, `azure-pipelines.yml`
  - Script: `scripts/AI-StoryPointEstimation.ps1`

- **Store and analyze estimation results**
  - Saves all estimations and historical data in `estimation-memory.db` (SQLite).
  - Script: `scripts/Initialize-EstimationDB.ps1`

- **Automate vulnerability ticket creation**
  - Scans npm dependencies for vulnerabilities and creates Azure DevOps work items for high/critical issues.
  - Pipeline: `azure-pipelines.yml` (see commented sections for security scan)
  - Script: `scripts/Security-VulnerabilityTickets.ps1`

- **Agent and AI service management**
  - Starts Azure DevOps agent and Ollama service automatically.
  - Script: `scripts/Agent-StartupScript.ps1`

All main scripts and pipeline YAML files are included in the `shared-project` folder. See below for setup instructions.

## Prerequisites

## AI Providers: Ollama & Groq

This project supports two AI providers for story point estimation:

- **Ollama (Local & Private):** Runs on your own machine for privacy and security. No data leaves your network. Default configuration uses Ollama.
- **Groq (Cloud):** Uses Groq's cloud API for fast and reliable estimation. Requires a Groq API key.

You can select the provider by setting the `AIProvider` parameter in the scripts or pipeline. For Groq, set your API key in `AI-StoryPointEstimation.ps1` (see the `GroqApiKey` parameter) or pass it as a parameter.

**Ollama Setup:**
Download Ollama from the official site: [https://ollama.com/download](https://ollama.com/download)
Follow the installation instructions for your operating system.
Ollama is started automatically by the `Agent-StartupScript.ps1` script. Make sure Ollama is installed and accessible on your machine.

**Groq Setup:**
- Obtain your Groq API key from your Groq account.

1. **Download and Configure Azure DevOps Agent**
   - Download the agent from the official Microsoft documentation: [Download Agent](https://learn.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops)
   - Follow the instructions to configure the agent for your organization and project.

2. **Initialize the SQLite Database**
   - Open PowerShell and navigate to the `scripts` folder in this project.
   - Run the following command to create the database:
     ```powershell
     .\Initialize-EstimationDB.ps1
     ```
   - This will create `estimation-memory.db` in the project root.

3. **Start the Agent and AI Service**
   - Run the agent startup script to start both the Azure DevOps agent and the local Ollama AI service:
     ```powershell
     .\Agent-StartupScript.ps1
     ```
   - Ensure Ollama is running and the agent is connected.

4. **Create User Stories on Your Azure DevOps Board**
   - Go to your Azure DevOps project board and create new User Stories.
   - The pipeline will automatically collect closed User Stories and estimate story points for new ones.

5. **Run the Pipeline**
   - The pipeline is scheduled to run automatically (see `azure-pipelines-learning.yml`).
   - You can also trigger it manually for testing.

## Notes
- All sensitive values (organization URL, project name, tokens) must be set as environment variables or pipeline secrets.
- The scripts are designed to be generic; replace placeholders in YAML and scripts with your own values as needed.
- For best results, ensure your board has historical User Stories with story points.

## Troubleshooting
- If the database is not created, ensure PSSQLite is installed and you have write permissions.
- If the agent does not start, verify the path in `Agent-StartupScript.ps1` and your agent configuration.
- For any authentication issues, check your PAT and permissions.

---

For more details, see the scripts and pipeline YAML files in this folder.

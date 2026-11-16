---
description: >
  Build, test, and (with HITL confirmation) publish a Blazor/.NET solution.
  Use when you need to build, compile, package, or deploy.
allowed-tools: Read, Grep, Glob, Write, Edit, Bash
---

# Build and Validate Blazor Solution

Your goal is to build and validate `${input:ProjectName}` for the `${input:DeploymentType}` environment (dev / staging / production).

## Step 1: Restore & Build

```bash
dotnet restore ${input:ProjectName}.sln
dotnet build ${input:ProjectName}.sln -c Release
```

Read the diagnostics. If a failure isn't obvious from the compiler output, use the **dotnet-msbuild-binlog** MCP server to analyze a binlog rather than re-running blind.

## Step 2: Test

```bash
dotnet test ${input:ProjectName}.sln
```

Report pass/fail counts. Do not proceed to publish guidance if tests fail — surface the failures instead.

## Step 3: Client AOT/Trimming Awareness

If the Client project has `RunAOTCompilation=true`/`PublishTrimmed=true`, warn that a full publish will take significantly longer than the build above and that AOT/trimming-only failures won't surface until:

```bash
dotnet publish ${ClientProjectPath} -c Release
```

## Step 4: Publish (🔒 Human Gate)

Publishing to a shared/live environment is a human or CI decision — present the commands, do not run them unprompted:

```bash
dotnet publish ${ServerProjectPath} -c Release
dotnet publish ${ServiceFnProjectPath} -c Release   # if the solution has Azure Functions
```

Confirm target environment, connection strings/Key Vault references, and any pending database migrations with the human before they run this.

## Step 5: Report

Summarize: build result, test results, any AOT/trimming risk flagged, and the exact publish commands for the human/CI to run.

function Parse-Configuration() {
    param(
        $SettingsFile
    )

    return Get-Content $SettingsFile | ConvertFrom-StringData
}

function Find-Records {
    param(
        $Records,
        $Name,
        $ParentId,
        $Type
    )

    $matchingRecords = @()
    for ($i = 0; $i -lt $Records.Length; $i++) {
        $record = $Records[$i]
        if ($record.type -eq $Type) {
            $condition = $true

            if ($null -ne $Name) {
                $condition = $condition -and $record.name -eq $Name
            }

            if ($null -ne $ParentId) {
                $condition = $condition -and $record.parentId -eq $ParentId
            }

            if ($condition -eq $true) {
                $matchingRecords += $record
            }
        }
    }

    return $matchingRecords
}

function Find-Record {
    param(
        $Records,
        $Name,
        $ParentId,
        $Type
    )

    $matchingRecords = Find-Records -Records $Records -Name $Name -ParentId $ParentId -Type $Type

    if ($matchingRecords.Length -eq 0) {
        Write-Host "No record found that matches criteria"
        return $null
    }
    elseif ($matchingRecords.Length -gt 1) {
        Write-Host "More than one matching record found"
        throw "More than one matching record found"
    }
    
    return $matchingRecords[0]
}

function Approve-Stage {
    param(
        $approval
    )

    $uriAccount = $baseUrl + "_apis/pipelines/approvals/?api-version=6.0-preview"

    # status = 4 means approved, because of reasons I guess =)
    $body = "
    [
        {
            ""approvalId"": ""$($approval.id)"",
            ""status"": ""4"",
            ""comment"": ""Approval by Build""
        }
    ]"
  
    Invoke-RestMethod -Uri $uriAccount -Method Patch -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json"
    Write-Host "Approved Stage"
}

function Get-VariableGroupId(){
    param(
        $VariableGroupName,
        $VariableGroups
    )
    
    for ($i = 0; $i -lt $VariableGroups.Length; $i++) {
        $variableGroup = $VariableGroups[$i]
        if ($variableGroup.name -eq $VariableGroupName) {
            return $variableGroup.id
        }
    }
}

function Get-VariableGroups() {
    $groups = @()
    $variableGroupUrl = $baseUrl + "_apis/distributedtask/variablegroups"
    $response = Invoke-RestMethod -Uri $variableGroupUrl -Method get -Headers $AzureDevOpsAuthenicationHeader 

    for ($i = 0; $i -lt $response.value.Length; $i++) {
        $groups += $response.value[$i]
    }

    return $groups
}

function Get-StageVariables() {
    param(
        $StageName
    )

    Write-Host "Checking Variables for Stage $($StageName)"
    $variableName = "$($StageName)_Variables"

    $variableGroups = @{}

    if ($configuration.ContainsKey($variableName)) {
        $variableString = $configuration."$($variableName)"
        Write-Host $variableString

        $splitVariables = $variableString.Split(',')
        for ($i = 0; $i -lt $splitVariables.Length; $i++) {
            $variabelGroupNameSplit = $splitVariables[$i].Split('.')
            $variableGroupName = $variabelGroupNameSplit[0]

            if (!$variableGroups.ContainsKey($variableGroupName)){
                $variableGroups[$variableGroupName] = @()
            }

            $variableGroups[$variableGroupName] += $variabelGroupNameSplit[1]
        }
    }
    else {
        Write-Host "No stage variables found for stage $($StageName)"
    }

    return $variableGroups
}

function Set-VariableGroupValues(){
    param(
        $VariableGroupId,
        $VariableGroupName,
        $Variables
    )

    $variableGroupUrl = $baseUrl + "_apis/distributedtask/variablegroups/$($VariableGroupId)?api-version=5.0-preview.1"
    $response = Invoke-RestMethod -Uri $variableGroupUrl -Method get -Headers $AzureDevOpsAuthenicationHeader

    $Variables.Keys | ForEach-Object {
        $response.variables.$_.value = $Variables.Item($_)
    }

    $variableString = ""
    $isFirstVariable = $true

    $response.variables.PSObject.Properties | ForEach-Object{
        if (!$isFirstVariable){
            $variableString += ","
        }

        $isFirstVariable = $false
        $isFirstProperty = $true

        $variableString += """$($_.Name)"": {"

        $_.Value.PSObject.Properties | ForEach-Object {
            if (!$isFirstProperty){
                $variableString += ","
            }

            $isFirstProperty = $false

            $variableString += """$($_.Name)"": ""$($_.Value)"""
        }

        $variableString += "}"
    }

    $body = "
    {
        ""id"": 2,
        ""type"": ""Vsts"",
        ""name"": ""$($VariableGroupName)"",
        ""variables"": {$($variableString)}
    }"

    $response = Invoke-RestMethod -Uri $variableGroupUrl -Method Put -Headers $AzureDevOpsAuthenicationHeader -Body $body -ContentType "application/json"

    Write-Host "Set Variables for group $($VariableGroupName)"
}

Write-Host "Reading settings file..."
$configuration = Parse-Configuration -SettingsFile "$($PSScriptRoot)\settings.txt"

Write-Host "==============================================="
Write-Host "Config"
Write-Host "==============================================="
Write-Host "Organization: $($configuration.OrganizationUrl)"
Write-Host "Team Project: $($configuration.TeamProject)"
Write-Host "Pipeline ID: $($configuration.PipelineId)"
Write-Host "Branch: $($configuration.Branch)"
Write-Host "==============================================="

$baseUrl = "$($configuration.OrganizationUrl)$($configuration.TeamProject)/"
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($configuration.PersonalAccessToken)")) }

$buildUrl = $baseUrl + "_apis/build/builds?definitions=$($configuration.PipelineId)&branchName=$($configuration.Branch)&statusFilter=inProgress"

Write-Host $buildUrl

$response = Invoke-RestMethod -Uri $buildUrl -Method get -Headers $AzureDevOpsAuthenicationHeader 

if ($response.value.Length -lt 1) {
    Write-Host "No builds in progress - exiting"
    exit
}

$inProgressBuilds = @()
Write-Host "Following Builds are in progress"

$response.value | ForEach-Object {
    Write-Host "Build $($_.buildNumber) (Id: $($_.id))"
    $inProgressBuilds += $_
}

$buildId = "-1"
$buildToInspect = Read-Host "Which build you want to inspect? (Hit enter for newest build)"

for ($i = 0; $i -lt $inProgressBuilds.Length; $i++) {
    $inProgressBuild = $inProgressBuilds[$i]

    if ($inProgressBuild.buildNumber -eq $buildToInspect) {
        $buildId = $inProgressBuild.id
        break
    }
}

if ($buildId -eq "-1") {
    $buildId = $inProgressBuilds[0].id
    
    Write-Host "Using latest build ($($inProgressBuilds.buildNumber))"
}

Write-Host "Latest build is: $($buildId) - getting stages..."

$timelineUrl = $baseUrl + "_apis/build/builds/$($buildId)/Timeline?api-version=5.1"
Write-Host $timelineUrl
$response = Invoke-RestMethod -Uri $timelineUrl -Method get -Headers $AzureDevOpsAuthenicationHeader 

$stages = Find-Records -Records $response.records -Type "Stage"
Write-Host "Found following Stages..."

$completedStages = @()
$inProgressStages = @()
$stagesWaitingForApproval = @()
$notStartedStages = @()

$stages | ForEach-Object {
    if ($_.state -eq "completed") {
        $completedStages += $_
    }
    elseif ($_.state -eq "inProgress"){
        $inProgressStages += $_
    }
    else {
        $checkPoint = Find-Record -Records $response.records -ParentId $_.id -Type "Checkpoint"
        if ($checkPoint -ne $null) {
            $approval = Find-Record -Records $response.records -ParentId $checkPoint.id -Type "Checkpoint.Approval"
            if ($approval.state -ne "completed") {
                $properties = @{
                    stage    = $_
                    approval = $approval
                }
                $stagesWaitingForApproval += New-Object psobject -Property $properties
            }
        }
        else{
            $notStartedStages += $_
        }
    }
}

Write-Host "-----------------"
Write-Host "Completed Stages"
Write-Host "-----------------"
$completedStages | Sort-Object -Property startTime | ForEach-Object {
    Write-Host "$($_.name) - $($_.result)"
}

Write-Host ""
Write-Host "-----------------"
Write-Host "In Progress Stages"
Write-Host "-----------------"
$inProgressStages | Sort-Object -Property startTime | ForEach-Object {
    Write-Host "$($_.name)"
}

Write-Host ""
Write-Host "-----------------"
Write-Host "Waiting for approval"
Write-Host "-----------------"
$stagesWaitingForApproval | ForEach-Object {    
    Write-Host "$($_.stage.name)"
}

Write-Host ""
Write-Host "-----------------"
Write-Host "Not yet started"
Write-Host "-----------------"
$notStartedStages | ForEach-Object {
    Write-Host "$($_.name) is not yet started"
}
Write-Host ""

$variableGroups = Get-VariableGroups

if ($stagesWaitingForApproval.Length -lt 1){
    Write-Host "No stage to approve - will exit"
    exit
}

$defaultStage = $stagesWaitingForApproval[0].stage.name

if (!($stageToApprove = Read-Host "Which stage to approve? (Hit enter for $($defaultStage))")) {
    $stageToApprove = $defaultStage
}

$stagesWaitingForApproval | ForEach-Object {
    if ($_.stage.name -eq $stageToApprove) {
        $stageVariables = Get-StageVariables -StageName $stageToApprove

        $stageVariables.Keys | ForEach-Object {
            $variableGroupId = Get-VariableGroupId -VariableGroupName $_ -VariableGroups $variableGroups

            $variableToValueMapping = @{}
            $variableGroupVariables = $stageVariables.Item($_)
            
            for ($i = 0; $i -lt $variableGroupVariables.Length; $i++){
                $variableName = $variableGroupVariables[$i]
                $variableToValueMapping[$variableName] = Read-Host "Please enter value for Variable $($variableName) from Variable Group $($_)"
            }

            Set-VariableGroupValues -VariableGroupId $variableGroupId -VariableGroupName $_ -Variables $variableToValueMapping
        }

        Write-Host "Approving Stage $($_.stage.name) (Id: $($_.stage.id))..."

        Approve-Stage -approval $_.approval
    }
}
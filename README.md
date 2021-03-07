# Azure Pipelines Release Approval
In order to stop a pipeline from executing all stages automatically you can create an environment and add an approver there. That will stop the stage from executing (e.g. when you don't want every pipeline run to execute something but perhaps only want it either on demand or every few hours/days).

This script will check the specified pipeline for all stages and see which ones are awaiting for an approval. Then it could auto-approve it.

The script also offers to set specified variables in a variable group before approving, for example if something needs to be changed for a stage to run (e.g. in case you need to everytime specify some password/MFA token before running the stage).

```
Reading settings file...
===============================================
Config
===============================================
Organization: https://dev.azure.com/huserben/
Team Project: MultistageBuild
Pipeline ID: 59
Branch: refs/heads/main
===============================================
https://dev.azure.com/huserben/MultistageBuild/_apis/build/builds?definitions=59&branchName=refs/heads/main&statusFilter=inProgress
Following Builds are in progress
Build 20210307.4 (Id: 3913)
Which build you want to inspect? (Hit enter for newest build):
Using latest build (20210307.4)
Latest build is: 3913 - getting stages...
https://dev.azure.com/huserben/MultistageBuild/_apis/build/builds/3913/Timeline?api-version=5.1
Found following Stages...
No record found that matches criteria
-----------------
Completed Stages
-----------------
Stage1 - succeeded

-----------------
In Progress Stages
-----------------

-----------------
Waiting for approval
-----------------
Stage2

-----------------
Not yet started
-----------------
Stage3 is not yet started

Which stage to approve? (Hit enter for Stage2):
Checking Variables for Stage Stage2
VariableGroup.ThisIsSomeFixedValue
Please enter value for Variable ThisIsSomeFixedValue from Variable Group VariableGroup: ThisIsSetFromTheScript
Set Variables for group VariableGroup
Approving Stage Stage2 (Id: feb4a670-8d1a-579f-6453-0b5a06576f62)...

Approved Stage
```

## Configuration
The configuration is done using a *settings.txt* file. You can check out the example file - rename it to *settings.txt* to run the script.

You need to specify your organization, team project, Personal Access Token (important as the PAT must belong to a user that can approve the stage) and the pipeline id of the pipeline you want to check together with the branch you want to check against.

### Variable Group Settings
In order to set variables you can add the following syntax to the settings file:

```
Stage2_Variables=VariableGroup.ThisIsSomeFixedValue
Stage3_Variables=VariableGroup.ThisIsSomeFixedValue,VariableGroup.ThisIsSomeFlexibleValue
```

This would cause the script, when approving *Stage2* to ask for input for a variable named *ThisIsSomeFixedValue* and that belongs to the Variable Group named *VariableGroup*.
You can also set more than one variable by separating the values with commas. The variables can be in different variable groups.

**Important:** If you have secret variables in your variable group, those values will be lost during the update as they cannot be read initially and the whole variable group will be set again with the provided values. Non-Secret values keep their original value. So it's a good idea to create a dedicated variable group with values that are all set from the script to not accidentally lose secret values.
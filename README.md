# AzureScaleSetManagement
Azure Virtual Machine Scale Set Management Tool

I have made this tool in PowerShell inspired by the tool Guy Bowerman made coded in Python.

You can check his tool at https://github.com/gbowerman/vmssdashboard

My tool has been coded in PowerShell using mostly the Azure REST API. The only exception is the login to Azure which is part of the AzureRM module. I made it this way to be easier for anyone to use it. In addition the required modules are automatically installed if not already installed. PowerShellGet is required to be installed or PowerShell 5.0 and above.

When running the Azure Scale Set Management tool, it will search for all Azure VM Scale Sets across all subscriptions the account you signed in has access to and provide that as a list to be selected.

The following are the functionalities once a scale set is selected:

1.  Start scale set VM instance(s)
2.  Deallocate scale set VM instance(s)
3.  Restart scale set VM instance(s)
4.  Reimage scale set VM instance(s)
5.  Delete scale set VM instance(s)
6.  Upgrade scale set VM instance(s)
7.  Roll out upgrade to all VM instances in batches
8.  Scale out / Scale in


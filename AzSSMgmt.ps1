#Import classes and initialise variables
$null = Add-Type -AssemblyName System.Windows.Forms
$null = Add-Type -AssemblyName System.Drawing
$script:buttonsToBeActioned = New-Object -TypeName System.Collections.ArrayList

#Get Token for API calls
Function Get-AccessToken {
    
  param
  (
    $tenantId
  )

  $cache = (Get-AzureRmContext).TokenCache
  $cacheItem = $cache.ReadItems() | Where-Object { $_.TenantId -eq $tenantId } #| Select-Object -First 1
  if($cacheItem.count -gt 1){

      $cacheItem = $cacheItem | Where-Object -Property DisplayableId -EQ $account

  }
  $header = @{
  
      'Authorization' = 'Bearer ' + $cacheItem.AccessToken
      'Content-Type' = 'application/json'
  }

  return $header
}


#Function to log in to Azure
Function Login-Azure{

  Try{
  
    $tenantId = (Get-AzureRmSubscription -WarningAction Ignore)[0].TenantId
    $script:requestHeader = Get-AccessToken -tenantId $tenantId

  }
  Catch{}

    if(!($script:requestHeader)){
  
      Try{
    
    $response = Invoke-WebRequest -Uri http://localhost:50342/oauth2/token -Method GET -Body @{resource="https://management.azure.com/"} -Headers @{Metadata="true"}
    $content = $response.Content | ConvertFrom-Json
    Write-Verbose -Message ('{0}' -f ('Signing in to Azure using Managed Service Identity...')) -Verbose
    $script:requestHeader = @{
  
      'Authorization' = 'Bearer ' + $content.access_token
      'Content-Type' = 'application/json'
    }
      }
      Catch{}
    if(!$script:requestHeader){

        #Check all requirements are in place if not install them
        Write-Verbose -Message ('{0}' -f ('Checking prerequisites are in place...')) -Verbose

        #Nugget is required to install the Azure module
        $nuget = (Get-PackageProvider -ListAvailable) | Where-Object Name -eq 'nuget'
        if($nuget.Name -eq 'Nuget' -and $nuget.Version -ge '2.8.5.208'){

          Write-Verbose -Message ('{0} version {1} found.' -f $nuget.Name, $nuget.Version) -Verbose

        }
        else{

          Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Verbose

        }

        Import-Module -Name AzureRM -ErrorAction SilentlyContinue
        $modules = Get-Module -Name AzureRM
        if(($modules.Name -eq 'AzureRM' -and $modules.Version -ge '4.2.1')){
  
          foreach($module in $modules){

            Write-Verbose -Message ('{0} version {1} found.' -f $module.Name, $module.Version) -Verbose

          }
        }
        #Install Azure module if it was not found
        else{

          Install-Module -Name AzureRM -Force -Verbose

        }

        Write-Verbose -Message ('{0}' -f ('Signing in to Azure using credentials...')) -Verbose
        $tenant = Add-AzureRmAccount
        $script:account = $tenant.Context.Account.Id
        $script:requestHeader = Get-AccessToken -tenantId $tenant.Context.Tenant.Id

    }
    
    $allScaleSets = Get-ScaleSets

  }
  else{

    $allScaleSets = Get-ScaleSets

  }
  
  return $allScaleSets
  
}

#Function to retrieve all scale sets from all subscriptions
Function Get-ScaleSets{

  $Uri = 'https://management.azure.com/subscriptions?api-version=2014-04-01'
  $subscriptions = (Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri).value
  
  ForEach ($subscription in $subscriptions){
   
    $Uri = "https://management.azure.com/subscriptions/$($subscription.SubscriptionId)/providers/Microsoft.Compute/virtualMachineScaleSets?api-version=2017-03-30"
    $scalesets = (Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri).value
      
    foreach($scaleset in $scalesets){

      $null = $ssDropdown.Items.Add($scaleset.Name.ToString())
      $allScaleSets += @{$scaleset.Name="$($scaleset.id.split('/')[-5]),$($scaleset.id.split('/')[-7])"}
      
    }
  }

    return $allScaleSets

}

#Function to create/update Button which represents a VM instance
Function New-ButtonStatus{

  param(
  
    [Parameter(Mandatory=$true)]$instanceNumber,
    [Parameter(Mandatory=$true)]$status
  
  )

  #If button does not exist, create a new one
  if($Buttons.Keys -notcontains $instanceNumber){

    $Button = new-object -TypeName System.Windows.Forms.Button
    $Button.Text = $instanceNumber
    $Button.Size = new-object -TypeName System.Drawing.Size -ArgumentList (30,30)
    $Button.ForeColor = [Drawing.Color]::Black
    $Button.FlatStyle = [Windows.Forms.FlatStyle]::Standard
    $Button.Add_Click{
      
      if($this.FlatAppearance.BorderColor.IsEmpty){

        $this.FlatStyle = [Windows.Forms.FlatStyle]::Flat
        $this.FlatAppearance.BorderColor = 'White'
        $this.FlatAppearance.BorderSize = 2
        $script:buttonsToBeActioned.Add($this)

      }
      else{

        $this.FlatStyle = [Windows.Forms.FlatStyle]::Standard
        $this.FlatAppearance.BorderColor = ''
        $this.FlatAppearance.BorderSize = 0
        $script:buttonsToBeActioned.Remove($this)

      }
    }

    $script:Buttons += @{$instanceNumber=$Button}
      
  }
  #if button exist just update status
  else{

    $Button = $Buttons.Item($instanceNumber)

  }

  Switch($status){

    'Running'          {$Button.BackColor = [Drawing.Color]::Green}
    'Stopping'         {$Button.BackColor = [Drawing.Color]::Yellow}
    'Stopped'          {$Button.BackColor = [Drawing.Color]::Red}
    'Starting'         {$Button.BackColor = [Drawing.Color]::Yellow}
    'Deallocating'     {$Button.BackColor = [Drawing.Color]::Red}
    'Deallocated'      {$Button.BackColor = [Drawing.Color]::Red}
    'Updating'         {$Button.BackColor = [Drawing.Color]::Yellow}
    'Deleting'         {$Button.BackColor = '#013D6F'}
    Default            {}


  }

  return $Button
  
}

#Get details of all VM instances part of the scale set
Function Get-ScaleSetDetails{

    $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/virtualMachines?`$expand=instanceView&`$select=instanceView&api-version=2017-03-30"
    Try{
    
      $instanceView = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri

    }
    Catch{
    
      #Azure limits the number of API calls per minute. If limit is reached connection is throttled.
      Write-Warning -Message 'Too many API calls. Azure has throttled the connection. Refresh temporarily changed to 120 seconds...'
      $script:timer.Interval=60000
      $script:countdownTimer.Interval = 500
      
    }
        
  return $instanceView

}

#Update status of the main form and table
Function Update-Status{
  
  #If there is a Roll Upgrade in progress, keep upgrading until all instances are done
    if($upgradeInProgress -eq $true){

        Roll-Upgrade -firstRun $false

    }

    $instances = Get-ScaleSetDetails

    foreach($instance in $instances.Value){
  
    if($instance.properties.instanceview.PlatformUpdateDomain.count){

      #Get the status of instances as well as their update and fault domains
      $status = Try{$instance.properties.instanceview.Statuses[1].Code.split('/')[1]}Catch{}
      $status0 = Try{$instance.properties.instanceview.Statuses[0].Code.split('/')[1]}Catch{}
      $UD = $instance.properties.instanceview.PlatformUpdateDomain + 1
      $FD = $instance.properties.instanceview.PlatformFaultDomain + 1
      $instanceNumber = $instance.instanceId
    
      if(($status0 -eq 'updating') -or ($status0 -eq 'deleting')){

        $status = $status0

      }
    
      if($status){

        #Creates a new button representing a single instance
        $objInstance = New-ButtonStatus -instanceNumber $instanceNumber -status $status

        #if button does not exist on table and there is another object in that table position
        if(($table.GetControlFromPosition($FD, $UD)) -and ($table.Controls -notcontains $objInstance)){
          
          #if objetct is a nested table
          if($table.GetControlFromPosition($FD, $UD).GetType().Name -eq 'TableLayoutPanel'){
        
            #If the button inside the nested table does not have the same status, add/refresh
            if($table.GetControlFromPosition($FD, $UD).GetControlFromPosition(($table.GetControlFromPosition($FD, $UD).GetColumnWidths().count) + 1, 0).Backcolor -ne $objInstance.BackColor){

              $table.GetControlFromPosition($FD, $UD).Controls.Add($objInstance, ($table.GetControlFromPosition($FD, $UD).GetColumnWidths().count) + 1, 0)
              
            }
          }
          #Create a new nested table, remove existing button in that cell, add to nested table and add new button as well
          else{

            $nestedTable = New-Object -TypeName System.Windows.Forms.TableLayoutPanel
            $nestedTable.AutoSize = $true
            $nestedTable.BackColor = '#013D6F'
            $nestedTable.Controls.Add($table.GetControlFromPosition($FD, $UD), ($nestedTable.GetColumnWidths().count), 0)
            $table.Controls.Remove($table.GetControlFromPosition($FD, $UD))
            $nestedTable.Controls.Add($objInstance, ($nestedTable.GetColumnWidths().count) + 1, 0)
            $table.Controls.Add($nestedTable, $FD, $UD)

          }
        }
        #If button does not have same status, add/refresh
        else{

          if($table.GetControlFromPosition($FD, $UD).Backcolor -ne $objInstance.BackColor){

            $table.Controls.Add($objInstance, $FD, $UD)

            }
        }
      }
    }
  }
  #Remove from the table buttons which represent instances which don't exist anymore
  foreach($buttonkey in $script:Buttons.Keys){

    if($instances.Value.instanceId -notcontains $buttonkey){

      $table.Controls.Remove($script:Buttons.item($buttonkey))
      foreach($nestedtable in $table.controls){

        $nestedTable.Controls.Remove($script:Buttons.item($buttonkey))

      }
      $buttonToBeRemoved += @($buttonkey)

    }
  }
  if($buttonToBeRemoved.count){
  
    foreach($button in $buttonToBeRemoved){
    
      $script:Buttons.Remove($button)

    }
  }

  $table.Visible = $true
  $actionDropdown.Visible = $true
  $pbRefresh.Value = 0
  $pbRefresh.Visible = $true
  $script:timer.Interval=20000
  $script:countdownTimer.Interval = 1000
    
}

#Roll upgrade to all instances in defined batches
Function Roll-Upgrade{

  param($firstRun)
              
  if($firstRun){

    $script:instancesToUpgrade = $null

    $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$($scaleset)?api-version=2017-03-30"
    $scaleConfig = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri
    $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.publisher = $imageTextBoxPublisher
    $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.offer = $imageTextBox.Text.split(' ')[0]
    $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.sku = $imageTextBoxSku = $imageTextBox.Text.split(' ')[1]
    $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.version = $imageTextBox.Text.split(' ')[2]
    $json = $scaleConfig | ConvertTo-Json -Depth 50
    $Result = Invoke-RestMethod -Method Patch -Headers $script:requestheader -Uri $Uri -Body $json 

    foreach($control in $table.Controls){

      if($control.Text -notlike '|*|'){

        if($control.GetType().Name -eq 'TableLayoutPanel'){
        
            foreach($subcontrol in $control.Controls){
            
                $script:positions += @{$subcontrol.Text = $table.GetCellPosition($control)}
            
            }
        
        }    
        else{

            $script:positions += @{$control.Text = $table.GetCellPosition($control)}

            }

      }
    }
  }

  if($instancesToUpgrade.count){
  #When a [System.Collections.DictionaryEntry] has only 1 item the GetEnumerators method does not work.
    if($script:instancesToUpgrade.count -eq 1){

      $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/virtualMachines/$($script:instancesToUpgrade.Name)/instanceView?api-version=2017-03-30"
      $Result = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri

      if($Result.Statuses[0].Code -like '*succeeded'){

          $script:instancesToUpgrade = $script:instancesToUpgrade | Where-Object Name -ne $script:instancesToUpgrade.Name
          Try{
            
            $script:positions.remove($script:instancesToUpgrade.Name)

          }
          Catch{}

      }
      else{return}

    }
    else{

      foreach($instance in $script:instancesToUpgrade.GetEnumerator().Name){

        $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/virtualMachines/$($instance)/instanceView?api-version=2017-03-30"
        $Result = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri

        if($Result.Statuses[0].Code -like '*succeeded'){

            $script:instancesToUpgrade = $script:instancesToUpgrade | Where-Object Name -ne $instance
            $script:positions.remove($instance)

        }
        else{return}

      }
    }
  }

  $script:instancesToUpgrade = $script:positions.GetEnumerator() | Sort-Object -Property Value | Select-Object -First $batchTextBox.Text

  if($script:positions.count){

    $script:upgradeInProgress = $true
    $Array = New-Object -TypeName System.Collections.ArrayList

    if($script:instancesToUpgrade.count -eq 1){

      $null = $array.add($script:instancesToUpgrade.Name)

    }
    else{
      foreach($key in $script:instancesToUpgrade.GetEnumerator().Name){

        $null = $array.add($key)   

      }
    }

    $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/manualUpgrade?api-version=2017-03-30"
    $instance = @{instanceIds=$array}
    $json = $instance | ConvertTo-Json
    $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json

  }
  else{

    $script:upgradeInProgress = $false

  }
}
#Main form
$Form = New-Object -TypeName System.Windows.Forms.Form
$Form.AutoSize = $true
$Form.Size = new-object -TypeName System.Drawing.Size -ArgumentList (350,200)
$Form.startposition = 'centerscreen'
$Form.Text = 'Azure Scale Set Management'
$Form.BackColor = '#013D6F'
$Form.ForeColor = 'White'
$Form.Add_KeyDown{if ($_.KeyCode -eq 'Escape'){$Form.Close()}}

#Scale set dropdown list
$ssDropdown = new-object -TypeName System.Windows.Forms.ComboBox
$ssDropdown.Location = new-object -TypeName System.Drawing.Size -ArgumentList (5,10)
$ssDropdown.Size = new-object -TypeName System.Drawing.Size -ArgumentList (170,70)
$ssDropdown.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$ssDropdown.ForeColor = '#013D6F'
$ssDropdown.Text = 'Select a Scale Set'

#Dropdown with available actions
$actionDropdown = new-object -TypeName System.Windows.Forms.ComboBox
$actionDropdown.Location = new-object -TypeName System.Drawing.Size -ArgumentList (180,10)
$actionDropdown.Size = new-object -TypeName System.Drawing.Size -ArgumentList (170,70)
$actionDropdown.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$actionDropdown.Visible = $false
$actionDropdown.ForeColor = '#013D6F'
$actionDropdown.Text = 'Action to Perform'
$actions = @('Start','Deallocate','Restart','Delete','Reimage','Upgrade','Roll Upgrade', 'Scale Out/In')
foreach($action in $actions){

  $null = $actionDropdown.Items.Add($action)

}

#Warning if no scale set is found or user does not have the required permissions
$noScaleSet = new-object -TypeName System.Windows.Forms.Label
$noScaleSet.Location = new-object -TypeName System.Drawing.Size -ArgumentList (5,50)
$noScaleSet.Size = new-object -TypeName System.Drawing.Size -ArgumentList (300,50)
$noScaleSet.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$noScaleSet.Text = "No scale set was found.`nMake sure you have the required permissions."
$noScaleSet.ForeColor = [Drawing.Color]::Yellow
 
#Labels for all Fault and Updade Domains
$FD0Label = new-object -TypeName System.Windows.Forms.Label
$FD0Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$FD0Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$FD0Label.Text = '| FD0 |'

$FD1Label = new-object -TypeName System.Windows.Forms.Label
$FD1Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$FD1Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)  
$FD1Label.Text = '| FD1 |'
  
$FD2Label = new-object -TypeName System.Windows.Forms.Label
$FD2Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$FD2Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$FD2Label.Text = '| FD2 |'
  
$FD3Label = new-object -TypeName System.Windows.Forms.Label
$FD3Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$FD3Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$FD3Label.Text = '| FD3 |'
  
$FD4Label = new-object -TypeName System.Windows.Forms.Label
$FD4Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$FD4Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$FD4Label.Text = '| FD4 |'
  
$UD0Label = new-object -TypeName System.Windows.Forms.Label
$UD0Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$UD0Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$UD0Label.Text = '| UD0 |'
  
$UD1Label = new-object -TypeName System.Windows.Forms.Label
$UD1Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$UD1Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$UD1Label.Text = '| UD1 |'
  
$UD2Label = new-object -TypeName System.Windows.Forms.Label
$UD2Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$UD2Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$UD2Label.Text = '| UD2 |'
  
$UD3Label = new-object -TypeName System.Windows.Forms.Label
$UD3Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$UD3Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$UD3Label.Text = '| UD3 |'
  
$UD4Label = new-object -TypeName System.Windows.Forms.Label
$UD4Label.Size = new-object -TypeName System.Drawing.Size -ArgumentList (100,100)
$UD4Label.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$UD4Label.Text = '| UD4 |'

#Progress bar with time until refresh
$pbRefresh = New-Object System.Windows.Forms.ProgressBar
$pbRefresh.Maximum = 20
$pbRefresh.Minimum = 0
$pbRefresh.Location = new-object System.Drawing.Size(5,42)
$pbRefresh.size = new-object System.Drawing.Size(345,30)
$pbRefresh.ForeColor = 'White'
$pbRefresh.Visible = $false
$script:countdownTimer = New-Object 'System.Windows.Forms.Timer'
$script:countdownTimer_Tick = {

    $pbRefresh.Increment(1)

}
$script:countdownTimer.Interval = 1000
$script:countdownTimer.add_Tick($script:countdownTimer_Tick)

#Textbox for image to be used in Upgrade
$imageTextBox = new-object -TypeName System.Windows.Forms.TextBox
$imageTextBox.Location = new-object -TypeName System.Drawing.Size -ArgumentList (355,10)
$imageTextBox.Size = new-object -TypeName System.Drawing.Size -ArgumentList (240,70)
$imageTextBox.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$imageTextBox.ForeColor = '#013D6F'
$imageTextBox.Visible = $false

#Textbox for number of instances to scale out/in
$scaleTextBox = new-object -TypeName System.Windows.Forms.TextBox
$scaleTextBox.Location = new-object -TypeName System.Drawing.Size -ArgumentList (355,10)
$scaleTextBox.Size = new-object -TypeName System.Drawing.Size -ArgumentList (50,70)
$scaleTextBox.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$scaleTextBox.ForeColor = '#013D6F'
$scaleTextBox.Visible = $false

#Textbox with batch number for roll upgrades
$batchTextBox = new-object -TypeName System.Windows.Forms.TextBox
$batchTextBox.Location = new-object -TypeName System.Drawing.Size -ArgumentList (355,40)
$batchTextBox.Size = new-object -TypeName System.Drawing.Size -ArgumentList (240,70)
$batchTextBox.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',12,[Drawing.FontStyle]::Bold)
$batchTextBox.ForeColor = '#013D6F'
$batchTextBox.Visible = $false
$batchTextBox.Text = 'Batch Size'

#Button to execure actions
$actionButton = new-object -TypeName System.Windows.Forms.Button
$actionButton.Location = new-object -TypeName System.Drawing.Size -ArgumentList (600,10)
$actionButton.Size = new-object -TypeName System.Drawing.Size -ArgumentList (45,30)
$actionButton.Font = New-Object -TypeName System.Drawing.Font -ArgumentList ('Arial',10,[Drawing.FontStyle]::Bold)
$actionButton.Text = 'GO'
$actionButton.Visible = $false
$actionButton.Add_MouseHover{$actionButton.BackColor = [Drawing.Color]::CornflowerBlue}
$actionButton.Add_MouseLeave{$actionButton.BackColor = '#013D6F'}
$actionButton.Add_Click{

    if(($script:buttonsToBeActioned.count) -or ($actionDropdown.SelectedItem -eq 'Scale Out/In') -or ($actionDropdown.SelectedItem -eq 'Roll Upgrade')){

        $Array = New-Object -TypeName System.Collections.ArrayList
        foreach($button in $script:buttonsToBeActioned){
            
            $button.FlatStyle = [Windows.Forms.FlatStyle]::Standard
            $button.FlatAppearance.BorderColor = ''
            $button.FlatAppearance.BorderSize = 0
            $Array.Add($button.Text)
            
        }
        switch($actionDropdown.SelectedItem){

            'Start'           {

                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/start?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()

            }
            'Deallocate'      {
            
                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/deallocate?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()
                        
            }
            'Restart'         {
            
                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/restart?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()

            }
            'Delete'          {
            
                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/delete?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()

            }
            'Reimage'         {
            
                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/reimage?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()

            }
            'Upgrade'         {
            
            if($script:buttonsToBeActioned.count){

                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$($scaleset)?api-version=2017-03-30"
                $scaleConfig = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri
                $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.publisher = $imageTextBoxPublisher
                $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.offer = $imageTextBox.Text.split(' ')[0]
                $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.sku = $imageTextBoxSku = $imageTextBox.Text.split(' ')[1]
                $scaleConfig.properties.virtualMachineProfile.storageProfile.imageReference.version = $imageTextBox.Text.split(' ')[2]
                $json = $scaleConfig | ConvertTo-Json -Depth 50
                $Result = Invoke-RestMethod -Method Patch -Headers $script:requestheader -Uri $Uri -Body $json
                $Array = New-Object -TypeName System.Collections.ArrayList
                
                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$scaleset/manualUpgrade?api-version=2017-03-30"
                $instance = @{instanceIds=$array}
                $json = $instance | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Post -Headers $script:requestheader -Uri $Uri -Body $json
                $script:buttonsToBeActioned.Clear()

            }
            }
            'Roll Upgrade'    {
                
            if($buttons.count){

                Roll-Upgrade -firstRun $true

            } 
        }
            'Scale Out/In'    {

                $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$($scaleset)?api-version=2017-03-30"
                $scaleConfig = @{sku=@{name=$scaleSetObj.Sku.Name;tier=$scaleSetObj.Sku.Tier;capacity=$scaleTextBox.Text}}
                $json = $scaleConfig | ConvertTo-Json
                $Result = Invoke-RestMethod -Method Patch -Headers $script:requestheader -Uri $Uri -Body $json   
            
            }
            Default           {}
        }
    }
}

#Main table
$table = New-Object -TypeName System.Windows.Forms.TableLayoutPanel
$table.Location = new-object -TypeName System.Drawing.Size -ArgumentList (5,75)
$table.AutoSize = $true
$table.BackColor = '#013D6F'
$table.CellBorderStyle = 'InSet'
$table.AutoSizeMode = 'GrowAndShrink'
$table.RowCount = 6
$table.ColumnCount = 6
$table.Visible = $false

#When value from scale set dropdown is selected
$ssDropdown.Add_SelectedIndexChanged{

  if($ssDropdown.SelectedIndex -ne -1){

    $script:scaleSet = ($ssDropdown.SelectedItem.ToString())
    $scaleSetDetails = $allScaleSets.($ssDropdown.SelectedItem.ToString())
    $script:subscription = $scaleSetDetails.split(',')[1]
    $script:resourceGroup = $scaleSetDetails.split(',')[0]
    
    $Uri = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.Compute/virtualMachineScaleSets/$($scaleset)?api-version=2017-03-30"
    $script:scaleSetObj = Invoke-RestMethod -Method Get -Headers $script:requestheader -Uri $Uri

    $imageTextBoxPublisher = $scalesetObj.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Publisher
    $imageTextBoxOffer = $scalesetObj.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Offer
    $imageTextBoxSku = $scalesetObj.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Sku
    $imageTextBoxVersion = $scalesetObj.Properties.VirtualMachineProfile.StorageProfile.ImageReference.Version
    $imageTextBox.Text = $imageTextBoxOffer + ' ' + $imageTextBoxSku + ' ' + $imageTextBoxVersion

    #Call Update-Status function and initialise timers
    $script:timer = New-Object -TypeName System.Windows.Forms.Timer
    Update-Status
    $script:timer.add_Tick{Update-Status}
    $script:timer.Start() #This timer refreshs the main table every minute
    $script:countdownTimer.Start() #This timer is used in conjunction with the progressbar
      
  }      
  if($Form.Visible -eq $false){

    $script:timer.stop()
    $form.Dispose()
    exit

  }
}

#When value from action dropdown is selected
$actionDropdown.Add_SelectedIndexChanged{

    if(($actionDropdown.SelectedItem) -eq 'Upgrade' -or ($actionDropdown.SelectedItem) -eq 'Roll Upgrade'){

      $imageTextBox.Visible = $true
      $actionButton.Visible = $true
      $scaleTextBox.Visible = $false
      $batchTextBox.Visible = $false

      if($actionDropdown.SelectedItem -eq 'Roll Upgrade'){

          $batchTextBox.Visible = $true

      }
    }
    elseif($actionDropdown.SelectedItem -eq 'Scale Out/In'){

      $scaleTextBox.Text = $scaleSetObj.Sku.Capacity
      $imageTextBox.Visible = $false
      $scaleTextBox.Visible = $true
      $actionButton.Visible = $true
      $batchTextBox.Visible = $false

    }
    else{

      $imageTextBox.Visible = $false
      $actionButton.Visible = $true
      $scaleTextBox.Visible = $false
      $batchTextBox.Visible = $false

    }
}

#First function to be called which initialises the script.
$allScaleSets = Login-Azure
if(!$allScaleSets){

  $Form.Controls.Add($noScaleSet)

}
$Form.Controls.Add($imageTextBox)
$Form.Controls.Add($scaleTextBox)
$Form.Controls.Add($batchTextBox)
$Form.Controls.Add($actionButton)
$Form.Controls.Add($table)
$table.Controls.Add($FD0Label, 1, 0)
$table.Controls.Add($FD1Label, 2, 0)
$table.Controls.Add($FD2Label, 3, 0)
$table.Controls.Add($FD3Label, 4, 0)
$table.Controls.Add($FD4Label, 5, 0)
$table.Controls.Add($UD0Label, 0, 1)
$table.Controls.Add($UD1Label, 0, 2)
$table.Controls.Add($UD2Label, 0, 3)
$table.Controls.Add($UD3Label, 0, 4)
$table.Controls.Add($UD4Label, 0, 5)
$Form.Controls.Add($pbRefresh)
$Form.Controls.Add($ssDropdown)
$Form.Controls.Add($actionDropdown)
$Form.Add_Shown{$Form.Activate()}
$Form.ShowDialog()

if($script:timer){

    $script:timer.stop()

}
if($script:countdownTimer){

    $script:countdownTimer.Stop()

}
Remove-Variable -Name form -ErrorAction SilentlyContinue
Remove-Variable -Name allScaleSets -ErrorAction SilentlyContinue
Remove-Variable -Name table -ErrorAction SilentlyContinue
Remove-Variable -Name SubDropDown -ErrorAction SilentlyContinue
Remove-Variable -Name instancesCount -ErrorAction SilentlyContinue
Remove-Variable -Name scaleSetObj -ErrorAction SilentlyContinue
Remove-Variable -Name imagePublisher -ErrorAction SilentlyContinue
Remove-Variable -Name imageOffer -ErrorAction SilentlyContinue
Remove-Variable -Name imageSku -ErrorAction SilentlyContinue
Remove-Variable -Name imageVersion -ErrorAction SilentlyContinue
Remove-Variable -Name jobs -ErrorAction SilentlyContinue
Remove-Variable -Name scaleSet -ErrorAction SilentlyContinue
Remove-Variable -Name resourceGroup -ErrorAction SilentlyContinue
Remove-Variable -Name SubscriptionID -ErrorAction SilentlyContinue
Remove-Variable -Name instancesToUpgrade -ErrorAction SilentlyContinue
Remove-Variable -Name UpgradeInProgress -ErrorAction SilentlyContinue
Remove-Variable -Name positions -ErrorAction SilentlyContinue
Remove-Variable -Name buttonsToBeActioned -ErrorAction SilentlyContinue
Remove-Variable -Name Buttons -ErrorAction SilentlyContinue
Remove-Variable -Name pbRefresh -ErrorAction SilentlyContinue
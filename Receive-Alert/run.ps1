using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

Write-Host "Processing Webhook for Alert - $($Request.Body.alertUID) -"

$HaloClientID = $env:HaloClientID
$HaloClientSecret = $env:HaloClientSecret
$HaloURL = $env:HaloURL

Write-Host "1"

$HaloTicketStatusID = $env:HaloTicketStatusID
$HaloCustomAlertTypeField = $env:HaloCustomAlertTypeField
$HaloTicketType = $env:HaloTicketType
$HaloReocurringStatus = $env:HaloReocurringStatus

Write-Host "2"

#Custom Env Vars
$DattoAlertUIDField = $env:DattoAlertUIDField

# Set if the ticket will be marked as responded in Halo
$SetTicketResponded = $True

# Relates the tickets in Halo if the alerts arrive within x minutes for a device.
$RelatedAlertMinutes = 5

# Creates a child ticket in Halo off the main ticket if it reocurrs with the specified number of hours.
$ReoccurringTicketHours = 24

$HaloAlertHistoryDays = 90

$PriorityHaloMap = @{
    "Critical"    = "4"
    "High"        = "4"
    "Moderate"    = "4"
    "Low"         = "4"
    "Information" = "4"
}

Write-Host "3"

$AlertWebhook = $Request.Body # | ConvertTo-Json -Depth 100

Write-Host "4"

$Email = Get-AlertEmailBody -AlertWebhook $AlertWebhook
Write-Host $Email
Write-host $AlertWebhook
Write-Host "5"

if ($Email) {
    $Alert = $Email.Alert

    Connect-HaloAPI -URL $HaloURL -ClientId $HaloClientID -ClientSecret $HaloClientSecret -Scopes "all"
    
    $HaloDeviceReport = @{
        name                    = "Datto RMM Improved Alerts PowerShell Function - Device Report"
        sql                     = "Select did, Dsite, DDattoID, DDattoAlternateId from device"
        description             = "This report is used to quickly obtain device mapping information for use with the improved Datto RMM Alerts Function"
        type                    = 0
        datasource_id           = 0
        canbeaccessedbyallusers = $false
    }

    $ParsedAlertType = Get-AlertHaloType -Alert $Alert -AlertMessage $AlertWebhook.alertMessage

    $HaloDevice = Invoke-HaloReport -Report $HaloDeviceReport -IncludeReport | where-object { $_.DDattoID -eq $Alert.alertSourceInfo.deviceUid }

    $HaloAlertsReportBase = @{
        name                    = "Datto RMM Improved Alerts PowerShell Function - Alerts Report"
        sql                     = "SELECT Faultid, Symptom, tstatusdesc, dateoccured, inventorynumber, FGFIAlertType, CFDattoAlertType, fxrefto as ParentID, fcreatedfromid as RelatedID FROM FAULTS inner join TSTATUS on Status = Tstatus Where CFDattoAlertType is not null and fdeleted <> 1"
        description             = "This report is used to quickly obtain alert information for use with the improved Datto RMM Alerts Function"
        type                    = 0
        datasource_id           = 0
        canbeaccessedbyallusers = $false
    }

    $HaloAlertsReport = Invoke-HaloReport -Report $HaloAlertsReportBase

    $AlertReportFilter = @{
        id                       = $HaloAlertsReport.id
        filters                  = @(
            @{
                fieldname      = 'inventorynumber'
                stringruletype = 2
                stringruletext = "$($HaloDevice.did)"
            }
        )
        _loadreportonly          = $true
        reportingperiodstartdate = get-date(((Get-date).ToUniversalTime()).adddays(-$HaloAlertHistoryDays)) -UFormat '+%Y-%m-%dT%H:%M:%SZ'
        reportingperiodenddate   = get-date((Get-date -Hour 23 -Minute 59 -second 59).ToUniversalTime()) -UFormat '+%Y-%m-%dT%H:%M:%SZ'
        reportingperioddatefield = "dateoccured"
        reportingperiod          = "7"
    }

    $ReportResults = (Set-HaloReport -Report $AlertReportFilter).report.rows

    $ReoccuringHistory = $ReportResults | where-object { $_.CFDattoAlertType -eq $ParsedAlertType } 
    
    $ReoccuringAlerts = $ReoccuringHistory | where-object { $_.dateoccured -gt ((Get-Date).addhours(-$ReoccurringTicketHours)) }

    $RelatedAlerts = $ReportResults | where-object { $_.dateoccured -gt ((Get-Date).addminutes(-$RelatedAlertMinutes)).ToUniversalTime() -and $_.CFDattoAlertType -ne $ParsedAlertType }
        
    $TicketSubject = $Email.Subject

    $HTMLBody = $Email.Body

    $HaloPriority = $PriorityHaloMap."$($Alert.Priority)"

    $RSiteDetails = $Request.Body.dattoSiteDetails

    Start-Sleep -Seconds 15

    $HaloSiteIDDatto = Find-DattoAlertHaloSite -DattoSiteName ($RSiteDetails)

    Write-Host ($RSiteDetails)

    $dattoLookupString = $Request.Body.dattoSiteDetails

    #Process based on naming scheme in Datto <site>(<Customer>)
    $dataSiteDetails = $dattoLookupString.Split("(").Split(")")
    #$DattoSite = $dataSiteDetails[0] 
    $DattoCustomer = $dataSiteDetails[1] 
    $HaloClientID = (Get-HaloClient -Search $DattoCustomer)[0].id

    $HaloClientDattoMatch = $HaloClientID
    
    Write-Host "Client ID in Halo $($HaloClientDattoMatch)"
    
    $Contracts = (Get-HaloContract -ClientID $HaloClientDattoMatch -FullObjects)

    Write-Host "Contracts for client ID are $($Contracts)"

    $FilteredContracts = $Contracts | Where-Object {
        $_.ref -like '*M' -and $_.site_id -eq $HaloSiteIDDatto
    }

    # Sort the filtered contracts by 'start_date' in descending order
    $LatestContract = $FilteredContracts | Sort-Object start_date -Descending | Select-Object -First 1

    Write-Host $LatestContract

    # Extract and display the ID of the latest contract based on the start date
    $LatestContractId = $LatestContract.id

    Write-Host $LatestContract.id

    $HaloTicketCreate = @{
        summary          = $TicketSubject
        tickettype_id    = 8
        details_html     = $HtmlBody
        DattoAlertState = 0
        site_id          = $HaloSiteIDDatto
        assets           = @(@{id = $HaloDevice.did })
        priority_id      = $HaloPriority
        status_id        = $HaloTicketStatusID
        category_1       = "Datto Alert"
        contract_id      = $LatestContractId
        customfields     = @(
            @{
                id    = $HaloCustomAlertTypeField
                value = $ParsedAlertType
            };
            @{
                id    = $DattoAlertUIDField
                value = $Request.Body.alertUID
            }
        )
    }

    # Your command to get tickets
    $TicketidGet = Get-HaloTicket -Category1 145 -OpenOnly -FullObjects

    # The UID you are looking for
    $targetUID = $Request.Body.alertUID #"d001df5e-ed49-4077-9479-fa7e3d08b121"

    # Iterate over each ticket in the result
    foreach ($ticket in $TicketidGet) {
        # Access the custom fields
        $customFields = $ticket.customfields

        # Find the field with name 'CFDattoAlertUID'
        $dattoAlertUIDField = $customFields | Where-Object { $_.name -eq 'CFDattoAlertUID' }

        # Check if the value of this field matches the target UID
        if ($dattoAlertUIDField -and $dattoAlertUIDField.value -eq $targetUID) {
            # Output the matching ticket ID
            Write-Output "Found matching ticket: ID is $($ticket.id)"
            $ticketidHalo = $ticket.id
            $dateArrival = (get-date((get-date).AddMinutes(-5)))
            $dateEnd = (get-date) 
            Write-Output "Date Arrival $($dateArrival) and end $($dateEnd)"
            
            $ActionUpdate = @{
                ticket_id         = $ticket.id
                actionid          = 23
                outcome           = "Remote"
                outcome_id        = 23
                note              = "Resolved by Datto Automation"
                actionarrivaldate = $dateArrival
                actioncompletiondate = $dateEnd
                action_isresponse = $false
                validate_response = $false
                sendemail         = $false
            }
            $Null = New-HaloAction -Action $ActionUpdate
            Write-Host "Adding ticket entry $ActionUpdate"
        }
    }

    Start-Sleep -Seconds 15
    
    if ($Request.Body.resolvedAlert -eq "true") {
        Write-Host "Resolved Closing $ticketidHalo"

        $TicketID = $ticketidHalo
        
        $TicketUpdate = @{
            id        = $TicketID 
            status_id = 9
            agent_id  = 38
        }
        $null = Set-HaloTicket -Ticket $TicketUpdate

        Start-Sleep -Seconds 1

        $Actions = Get-HaloAction -TicketID $TicketID

        # Mass review logic
        foreach ($action in $actions) {
           $ReviewData = @{
               ticket_id = $action.ticket_id
               id = $action.id
               actreviewed = "true"
            }
            Set-HaloAction -Action $ReviewData
        }
        
        Start-Sleep -Seconds 1

        $dateInvoice = (get-date)
        $invoice = @{ 
            client_id = $HaloClientDattoMatch
            invoice_date = $dateInvoice
            lines = @(@{entity_type = "labour";ticket_id = $TicketID})
        }

        New-HaloInvoice -Invoice $invoice 
        
    } else {
        Write-Host "Creating Ticket"
        $Ticket = New-HaloTicket -Ticket $HaloTicketCreate

        # Handle Specific Ticket responses based on ticket subject type
        # Check if the alert message contains the specific disk usage alert for the C: drive
        if ($TicketSubject -like "*Alert: Disk Usage - C:*") {
            # Perform your action here
            Write-Host "Alert detected for high disk usage on C: drive. Taking action..."

            #Needs to send email to user
            #Look up from Datto 365 integration? or 365 AAD lookup? or Halo contacts list? 
            
        }   
    }

    $HaloTicketCreate | Out-String | Write-Host

} else {
        Write-Host "No alert found"
}



# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = ''
    })

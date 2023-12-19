function GetUserEmail {
    param (
        $Username,
        $ClientId
    )
    #Get Email address based on provided username. 

    $address = (Get-HaloUser -Search $username -ClientID $ClientId).emailaddress

    if ($null -eq $address) {
        return $false
    } else { 
        return $address
    }
    
}

function SendResponse {
    param (
        $EmailAddress,
        $EmailMessage,
        $TicketId
    )
    #Send the request through Halo to send an email. 
    $dateArrival = (get-date((get-date).AddMinutes(-1)))
    $dateEnd = (get-date) 
    
    $ActionUpdate = @{
        ticket_id               = $TicketId
        outcome                 = "Email User"
        outcome_id              = 16
        emailfrom               = "IT Support"
        replytoaddress          = "helpdesk@aegis-group.co.uk"
        emailto                 = $EmailAddress
        #emailsubject           = ""
        note                    = $EmailMessage
        actionarrivaldate       = $dateArrival
        actioncompletiondate    = $dateEnd
        action_isresponse       = $false
        validate_response       = $false
        sendemail               = $true
    }

    $Null = New-HaloAction -Action $ActionUpdate
}

function FindSendResponse {
    param (
        $Username,
        $clientid,
        $EmailMessage,
        $TicketId
    )

    $EmailAddress = GetUserEmail -Username $Username -ClientId $clientid

    if ($null = $EmailAddress) {
        return $false
    }

    #Send the request through Halo to send an email. 
    $dateArrival = (get-date((get-date).AddMinutes(-1)))
    $dateEnd = (get-date) 
    
    $ActionUpdate = @{
        ticket_id               = $TicketId
        outcome                 = "Email User"
        outcome_id              = 16
        emailfrom               = "IT Support"
        replytoaddress          = "helpdesk@aegis-group.co.uk"
        emailto                 = $EmailAddress
        #emailsubject           = ""
        note                    = $EmailMessage
        actionarrivaldate       = $dateArrival
        actioncompletiondate    = $dateEnd
        action_isresponse       = $false
        validate_response       = $false
        sendemail               = $true
    }

    $Null = New-HaloAction -Action $ActionUpdate

    return $true
}


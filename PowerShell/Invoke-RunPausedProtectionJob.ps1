[CmdletBinding()]
param(
  # Cohesity Cluster
  [Parameter(Mandatory=$false)]
  [string]
  $Server,
  # Cohesity Credential
  [Parameter(Mandatory=$false)]
  [pscredential]
  $Credential,
  # Parameter help description
  [Parameter(Mandatory=$true)]
  [string]
  $ProtectionJob
)

function Main {
  Import-Module Cohesity.PowerShell.Core
  if (-not [string]::IsNullOrEmpty($Server) -and -not [string]::IsNullOrEmpty($Credential)) {
    $result = Connect-CohesityCluster -Server $Server -Credential $Credential
  }
  elseif ([string]::IsNullOrEmpty($Session) -or $Session.ApiClient.IsAuthenticated -eq $false) {
    Write-Error "Failed to authenticate. Please connect to the Cohesity Cluster using 'Connect-CohesityCluster'"
  }

  try{
    $result = Get-CohesityProtectionJob -Ids $ProtectionJob -ErrorAction SilentlyContinue
  }
  catch {
    $result = Get-CohesityProtectionJob -Names $ProtectionJob
  }

  if (-not $result.Id) {
    Write-Error "Failed to find protection job '$ProtectionJob'"
  }

  Invoke-CohesityAPI -RequestMethod 'POST' -RequestTarget "protectionJobState/$($result.Id)" -RequestArguments @{ pause = $false }
  Write-Output "Un-paused protection job $($result.Name)"
  Start-Sleep -Seconds 15
  Write-Output "Paused protection job $($result.Name)"
  Invoke-CohesityAPI -RequestMethod 'POST' -RequestTarget "protectionJobState/$($result.Id)" -RequestArguments @{ pause = $true }
}

function Invoke-CohesityAPI {
  [CmdletBinding()]
  param (
    # Method
    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'post', 'put', 'delete')]
    [String]
    $RequestMethod,
    # URI
    [Parameter(Mandatory = $true)]
    [String]
    $RequestTarget,
    # Data Payload
    [Parameter(Mandatory = $false)]
    [hashtable]
    $RequestArguments,
    # Request Headers
    [Parameter(Mandatory = $false)]
    [hashtable]$RequestHeaders = @{}
  )

  begin {
    # Set minimum required headers
    $RequestHeaders['accept'] = 'application/json'

    # Validate that we have a target VIP
    if ($RequestMethod -ieq "POST" -and $RequestTarget -match "accessTokens") {
      # Continue on to authenticate new session
    }
    elseif ([string]::IsNullOrEmpty($Session) -or $Session.ApiClient.IsAuthenticated -eq $false) {
      Write-Error "Failed to authenticate. Please connect to the Cohesity Cluster using 'Connect-CohesityCluster'"
    }
    else {
      $RequestHeaders['Authorization'] = "$($Session.ApiClient.AccessToken.TokenType) $($Session.ApiClient.AccessToken.AccessToken)"
    }
  }

  process {
    # Create full URI based on RequestTarget
    $uri = "https://$($script:CohesityServer)"
    # If requestTarget starts with a "/" then use it verbatim otherwise prefix with public
    if ($RequestTarget[0] -ne "/") {
      $RequestTarget = "public/$RequestTarget"
    }
    else {
      $RequestTarget = $RequestTarget[1..-1]
    }
    # Assemble the complete URI for the short resource name

    [string]$uri = (New-Object -TypeName 'System.Uri' -ArgumentList $Session.ApiClient.HttpClient.BaseAddress, $RequestTarget).ToString()
    # If RequestMethod is GET then put parameters on URI
    if ( $RequestMethod -ieq 'get' ) {
      if ($RequestArguments.Count -gt 0) {
        $uri += '?'
        $uri += [string]::join("&", @(
            foreach ($pair in $RequestArguments.GetEnumerator()) {
              if ($pair.Name) {
                $pair.Name + '=' + $pair.Value
              }
            }))
      }
      try {
        $result = Invoke-RestMethod `
          -Method 'GET' `
          -ContentType 'application/json' `
          -Headers $RequestHeaders `
          -Uri $uri
      }
      catch {
        Write-Error $_.Exception.Message
      }
    }
    # All other request methods will send a JSON payload
    else {
      $body = $RequestArguments | ConvertTo-Json -Depth 100
      try {
        $result = Invoke-RestMethod `
          -Method $RequestMethod `
          -Headers $RequestHeaders `
          -ContentType 'application/json' `
          -Uri $uri `
          -Body $body
      }
      catch {
        Write-Error $_.Exception.Message
      }
    }

    Return $result
  }

  end {
  }
}



# Disable SSL checking for communication to the array
if ($PSVersionTable.PSVersion.Major -ge "6") {
  try {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck",$true)
  } catch {}
}
else {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
    Add-Type @"
      using System;
      using System.Net;
      using System.Net.Security;
      using System.Security.Cryptography.X509Certificates;
      public class ServerCertificateValidationCallback {
        public static void Ignore() {
          ServicePointManager.ServerCertificateValidationCallback +=
            delegate (
              Object obj,
              X509Certificate certificate,
              X509Chain chain,
              SslPolicyErrors errors
            ) { return true; };
        }
      }
"@
  }
  [ServerCertificateValidationCallback]::Ignore()
}

$ErrorActionPreference = "Stop"

Main
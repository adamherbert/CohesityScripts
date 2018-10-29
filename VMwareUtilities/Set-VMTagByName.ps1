param (
  [Parameter(Mandatory=$true)]
  [string]$VCenterServer,

  [Parameter(Mandatory=$false)]
  [PSCredential]$VCenterCredential,

  [Parameter(Mandatory=$true)]
  [string]$VMName,

  [Parameter(Mandatory=$true)]
  [string]$TagName,

  [Parameter(Mandatory=$false)]
  [switch]$RemoveTag=$false
)

Import-Module VMware.VimAutomation.Core

if ($VCenterCredential) {
  Connect-VIServer -Server $VCenterServer -Credential $VCenterCredential  | Out-Null
}
else {
  Connect-VIServer -Server $VCenterServer | Out-Null
}

if ($TagName -match "/") {
  $TagCategory, $TagName = $TagName -split "/"
}
$TagObject = Get-Tag -Category $TagCategory -Name $TagName -ErrorAction Stop

if ($RemoveTag.ToBool()) {
  Get-VM -Name $VMName | Get-TagAssignment | Where-Object { $_.Tag -eq $TagObject } | Remove-TagAssignment -Confirm:$false
}
else {
  Get-VM -Name $VMName | New-TagAssignment -Tag $TagObject -ErrorAction SilentlyContinue
}

Get-VM -Name $VMName | Select-Object Name, @{ Name="Tag"; Expression = {$_ | Get-TagAssignment | Select-Object -ExpandProperty Tag}} | Format-Table
function Get-PodeTimer
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    return $PodeContext.Timers[$Name]
}

function Start-PodeTimerRunspace
{
    if ((Get-PodeCount $PodeContext.Timers) -eq 0) {
        return
    }

    $script = {
        while ($true)
        {
            $_remove = @()
            $_now = [DateTime]::Now

            $PodeContext.Timers.Values | Where-Object { $_.NextTick -le $_now } | ForEach-Object {
                $run = $true

                # increment total number of runs for timer (do we still need to count?)
                if ($_.Countable) {
                    $_.Count++
                    $_.Countable = ($_.Count -lt $_.Skip -or $_.Count -lt $_.Limit)
                }

                # check if this run should be skipped
                if ($_.Count -lt $_.Skip) {
                    $run = $false
                }

                # check if we have hit the limit, and remove
                if ($run -and $_.Limit -ne 0 -and $_.Count -ge $_.Limit) {
                    $run = $false
                    $_remove += $_.Name
                }

                if ($run) {
                    try {
                        Invoke-PodeScriptBlock -ScriptBlock $_.Script -Arguments @{ 'Lockable' = $PodeContext.Lockable } -Scoped
                    }
                    catch {
                        $Error[0]
                    }

                    $_.NextTick = $_now.AddSeconds($_.Interval)
                }
            }

            # remove any timers
            $_remove | ForEach-Object {
                $PodeContext.Timers.Remove($_)
            }

            Start-Sleep -Seconds 1
        }
    }

    Add-PodeRunspace -Type 'Main' -ScriptBlock $script
}
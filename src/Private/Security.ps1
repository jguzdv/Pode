function Test-PodeIPLimit
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $IP
    )

    $type = 'IP'

    # get the ip address in bytes
    $IP = @{
        'String' = $IP.IPAddressToString;
        'Family' = $IP.AddressFamily;
        'Bytes' = $IP.GetAddressBytes();
    }

    # get the limit rules and active list
    $rules = $PodeContext.Server.Limits.Rules[$type]
    $active = $PodeContext.Server.Limits.Active[$type]
    $now = [DateTime]::UtcNow

    # if there are no rules, it's valid
    if (Test-IsEmpty $rules) {
        return $true
    }

    # is the ip active? (get a direct match, then try grouped subnets)
    $_active_ip = $active[$IP.String]
    if ($null -eq $_active_ip) {
        $_groups = @(foreach ($key in $active.Keys) {
            if ($active[$key].Rule.Grouped) {
                $active[$key]
            }
        })

        $_active_ip = @(foreach ($_group in $_groups) {
            if (Test-PodeIPAddressInRange -IP $IP -LowerIP $_group.Rule.Lower -UpperIP $_group.Rule.Upper) {
                $_group
            }
        })[0]
    }

    # the ip is active, or part of a grouped subnet
    if ($null -ne $_active_ip) {
        # if limit is -1, always allowed
        if ($_active_ip.Rule.Limit -eq -1) {
            return $true
        }

        # check expire time, a reset if needed
        if ($now -ge $_active_ip.Expire) {
            $_active_ip.Rate = 0
            $_active_ip.Expire = $now.AddSeconds($_active_ip.Rule.Seconds)
        }

        # are we over the limit?
        if ($_active_ip.Rate -ge $_active_ip.Rule.Limit) {
            return $false
        }

        # increment the rate
        $_active_ip.Rate++
        return $true
    }

    # the ip isn't active
    else {
        # get the ip's rule
        $_rule_ip = @(foreach ($rule in $rules.Values) {
            if (Test-PodeIPAddressInRange -IP $IP -LowerIP $rule.Lower -UpperIP $rule.Upper) {
                $rule
            }
        })[0]

        # if ip not in rules, it's valid
        # (add to active list as always allowed - saves running where search everytime)
        if ($null -eq $_rule_ip) {
            $active.Add($IP.String, @{
                'Rule' = @{
                    'Limit' = -1
                }
            })

            return $true
        }

        # add ip to active list (ip if not grouped, else the subnet if it's grouped)
        $_ip = (Resolve-PodeValue -Check $_rule_ip.Grouped -TrueValue $_rule_ip.IP -FalseValue $IP.String)

        $active.Add($_ip, @{
            'Rule' = $_rule_ip;
            'Rate' = 1;
            'Expire' = $now.AddSeconds($_rule_ip.Seconds);
        })

        # if limit is 0, it's never allowed
        return ($_rule_ip -ne 0)
    }
}

function Test-PodeIPAccess
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $IP
    )

    $type = 'IP'

    # get the ip address in bytes
    $IP = @{
        'Family' = $IP.AddressFamily;
        'Bytes' = $IP.GetAddressBytes();
    }

    # get permission lists for ip
    $allow = $PodeContext.Server.Access.Allow[$type]
    $deny = $PodeContext.Server.Access.Deny[$type]

    # are they empty?
    $alEmpty = (Test-IsEmpty $allow)
    $dnEmpty = (Test-IsEmpty $deny)

    # if both are empty, value is valid
    if ($alEmpty -and $dnEmpty) {
        return $true
    }

    # if value in allow, it's allowed
    if (!$alEmpty) {
        $match = @(foreach ($value in $allow.Values) {
            if (Test-PodeIPAddressInRange -IP $IP -LowerIP $value.Lower -UpperIP $value.Upper) {
                $value
            }
        })[0]

        if ($null -ne $match) {
            return $true
        }
    }

    # if value in deny, it's disallowed
    if (!$dnEmpty) {
        $match = @(foreach ($value in $deny.Values) {
            if (Test-PodeIPAddressInRange -IP $IP -LowerIP $value.Lower -UpperIP $value.Upper) {
                $value
            }
        })[0]

        if ($null -ne $match) {
            return $false
        }
    }

    # if we have an allow, it's disallowed (because it's not in there)
    if (!$alEmpty) {
        return $false
    }

    # otherwise it's allowed (because it's not in the deny)
    return $true
}

function Add-PodeIPLimit
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [string]
        $IP,

        [Parameter(Mandatory=$true)]
        [int]
        $Limit,

        [Parameter(Mandatory=$true)]
        [int]
        $Seconds,

        [switch]
        $Group
    )

    # current limit type
    $type = 'IP'

    # ensure limit and seconds are non-zero and negative
    if ($Limit -le 0) {
        throw "Limit value cannot be 0 or less for $($IP)"
    }

    if ($Seconds -le 0) {
        throw "Seconds value cannot be 0 or less for $($IP)"
    }

    # get current rules
    $rules = $PodeContext.Server.Limits.Rules[$type]

    # setup up perm type
    if ($null -eq $rules) {
        $PodeContext.Server.Limits.Rules[$type] = @{}
        $PodeContext.Server.Limits.Active[$type] = @{}
        $rules = $PodeContext.Server.Limits.Rules[$type]
    }

    # have we already added the ip?
    elseif ($rules.ContainsKey($IP)) {
        return
    }

    # calculate the lower/upper ip bounds
    if (Test-PodeIPAddressIsSubnetMask -IP $IP) {
        $_tmp = Get-PodeSubnetRange -SubnetMask $IP
        $_tmpLo = Get-PodeIPAddress -IP $_tmp.Lower
        $_tmpHi = Get-PodeIPAddress -IP $_tmp.Upper
    }
    elseif (Test-PodeIPAddressAny -IP $IP) {
        $_tmpLo = Get-PodeIPAddress -IP '0.0.0.0'
        $_tmpHi = Get-PodeIPAddress -IP '255.255.255.255'
    }
    else {
        $_tmpLo = Get-PodeIPAddress -IP $IP
        $_tmpHi = $_tmpLo
    }

    # add limit rule for ip
    $rules.Add($IP, @{
        'Limit' = $Limit;
        'Seconds' = $Seconds;
        'Grouped' = [bool]$Group;
        'IP' = $IP;
        'Lower' = @{
            'Family' = $_tmpLo.AddressFamily;
            'Bytes' = $_tmpLo.GetAddressBytes();
        };
        'Upper' = @{
            'Family' = $_tmpHi.AddressFamily;
            'Bytes' = $_tmpHi.GetAddressBytes();
        };
    })
}

function Add-PodeIPAccess
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet('Allow', 'Deny')]
        [string]
        $Permission,

        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [string]
        $IP
    )

    # current access type
    $type = 'IP'

    # get opposite permission
    $opp = "$(if ($Permission -ieq 'allow') { 'Deny' } else { 'Allow' })"

    # get permission lists for type
    $permType = $PodeContext.Server.Access[$Permission][$type]
    $oppType = $PodeContext.Server.Access[$opp][$type]

    # setup up perm type
    if ($null -eq $permType) {
        $PodeContext.Server.Access[$Permission][$type] = @{}
        $permType = $PodeContext.Server.Access[$Permission][$type]
    }

    # have we already added the ip?
    elseif ($permType.ContainsKey($IP)) {
        return
    }

    # remove from opp type
    if ($null -ne $oppType -and $oppType.ContainsKey($IP)) {
        $oppType.Remove($IP)
    }

    # calculate the lower/upper ip bounds
    if (Test-PodeIPAddressIsSubnetMask -IP $IP) {
        $_tmp = Get-PodeSubnetRange -SubnetMask $IP
        $_tmpLo = Get-PodeIPAddress -IP $_tmp.Lower
        $_tmpHi = Get-PodeIPAddress -IP $_tmp.Upper
    }
    elseif (Test-PodeIPAddressAny -IP $IP) {
        $_tmpLo = Get-PodeIPAddress -IP '0.0.0.0'
        $_tmpHi = Get-PodeIPAddress -IP '255.255.255.255'
    }
    else {
        $_tmpLo = Get-PodeIPAddress -IP $IP
        $_tmpHi = $_tmpLo
    }

    # add access rule for ip
    $permType.Add($IP, @{
        'Lower' = @{
            'Family' = $_tmpLo.AddressFamily;
            'Bytes' = $_tmpLo.GetAddressBytes();
        };
        'Upper' = @{
            'Family' = $_tmpHi.AddressFamily;
            'Bytes' = $_tmpHi.GetAddressBytes();
        };
    })
}

function Set-PodeCsrfSetup
{
    param (
        [Parameter()]
        [ValidateSet('DELETE', 'GET', 'HEAD', 'MERGE', 'OPTIONS', 'PATCH', 'POST', 'PUT', 'TRACE', 'STATIC')]
        [string[]]
        $IgnoreMethods = @('GET', 'HEAD', 'OPTIONS', 'TRACE', 'STATIC'),

        [Parameter()]
        [string]
        $Secret,

        [switch]
        $Cookie
    )

    # check that csrf logic hasn't already been defined
    if (!(Test-IsEmpty $PodeContext.Server.Cookies.Csrf)) {
        return
    }

    # if sessions haven't been setup and we're not using cookies, error
    if (!$Cookie -and (Test-IsEmpty $PodeContext.Server.Cookies.Session)) {
        throw 'Sessions are required to use CSRF unless you pass the -Cookie flag'
    }

    # if we're using cookies, ensure a global secret exists
    if ($Cookie) {
        $Secret = (Protect-PodeValue -Value $Secret -Default (Get-PodeCookieSecret -Global))

        if (Test-IsEmpty $Secret) {
            throw "When using cookies for CSRF, a secret is required. You can either supply a secret, or set the cookie global secret - (Set-PodeCookieSecret '<value>' -Global)"
        }
    }

    # set the options against the server context
    $PodeContext.Server.Cookies.Csrf = @{
        'Name' = 'pode.csrf';
        'Cookie' = $Cookie;
        'Secret' = $Secret;
        'IgnoredMethods' = $IgnoreMethods;
    }
}

function Get-PodeCsrfMiddleware
{
    # check that csrf logic has been defined
    if (Test-IsEmpty $PodeContext.Server.Cookies.Csrf) {
        throw 'CSRF middleware has not been defined'
    }

    # return scriptblock for the csrf middleware
    return {
        param($e)

        # if the current route method is ignored, just return
        $ignored = @($PodeContext.Server.Cookies.Csrf.IgnoredMethods)
        if (!(Test-IsEmpty $ignored) -and ($ignored -icontains $e.Method)) {
            return $true
        }

        # if there's not a secret, generate and store it
        $secret = New-PodeCsrfSecret

        # verify the token on the request, if invalid, throw a 403
        $token = Get-PodeCsrfToken

        if (!(Test-PodeCsrfToken -Secret $secret -Token $token)){
            Set-PodeResponseStatus -Code 403 -Description 'Invalid CSRF Token'
            return $false
        }

        # token is valid, move along
        return $true
    }
}

function Get-PodeCsrfCheck
{
    # check that csrf logic has been defined
    if (Test-IsEmpty $PodeContext.Server.Cookies.Csrf) {
        throw 'CSRF middleware has not been defined'
    }

    # return scriptblock for the csrf check middleware
    return {
        param($e)

        # if there's not a secret, generate and store it
        $secret = New-PodeCsrfSecret

        # verify the token on the request, if invalid, throw a 403
        $token = Get-PodeCsrfToken

        if (!(Test-PodeCsrfToken -Secret $secret -Token $token)){
            Set-PodeResponseStatus -Code 403 -Description 'Invalid CSRF Token'
            return $false
        }

        # token is valid, move along
        return $true
    }
}

function Get-PodeCsrfToken
{
    # key name to search
    $key = $PodeContext.Server.Cookies.Csrf.Name

    # check the payload
    if (!(Test-IsEmpty $WebEvent.Data[$key])) {
        return $WebEvent.Data[$key]
    }

    # check the query string
    if (!(Test-IsEmpty $WebEvent.Query[$key])) {
        return $WebEvent.Query[$key]
    }

    # check the headers
    $value = (Get-PodeHeader -Name $key)
    if (!(Test-IsEmpty $value)) {
        return $value
    }

    return $null
}

function Test-PodeCsrfToken
{
    param (
        [Parameter()]
        [string]
        $Secret,

        [Parameter()]
        [string]
        $Token
    )

    # if there's no token/secret, fail
    if ((Test-IsEmpty $Secret) -or (Test-IsEmpty $Token)) {
        return $false
    }

    # the token must start with "t:"
    if (!$Token.StartsWith('t:')) {
        return $false
    }

    # get the salt from the token
    $_token = $Token.Substring(2)
    $periodIndex = $_token.LastIndexOf('.')
    if ($periodIndex -eq -1) {
        return $false
    }

    $salt = $_token.Substring(0, $periodIndex)

    # ensure the token is valid
    if ((New-PodeCsrfToken -Secret $Secret -Salt $salt) -ne $Token) {
        return $false
    }

    return $true
}

function New-PodeCsrfSecret
{
    # see if there's already a secret in session/cookie
    $secret = (Get-PodeCsrfSecret)
    if (!(Test-IsEmpty $secret)) {
        return $secret
    }

    # otherwise, make a new secret and cache it
    $secret = (New-PodeGuid -Secure -Length 16)
    Set-PodeCsrfSecret -Secret $secret
    return $secret
}

function Get-PodeCsrfSecret
{
    # key name to get secret
    $key = $PodeContext.Server.Cookies.Csrf.Name

    # are we getting it from a cookie, or session?
    if ($PodeContext.Server.Cookies.Csrf.Cookie) {
        return (Get-PodeCookie `
            -Name $PodeContext.Server.Cookies.Csrf.Name `
            -Secret $PodeContext.Server.Cookies.Csrf.Secret).Value
    }

    # on session
    else {
        return $WebEvent.Session.Data[$key]
    }
}

function Set-PodeCsrfSecret
{
    param (
        [Parameter(Mandatory=$true)]
        [string]
        $Secret
    )

    # key name to set secret under
    $key = $PodeContext.Server.Cookies.Csrf.Name

    # are we setting this on a cookie, or session?
    if ($PodeContext.Server.Cookies.Csrf.Cookie) {
        (Set-PodeCookie `
            -Name $PodeContext.Server.Cookies.Csrf.Name `
            -Value $Secret `
            -Secret $PodeContext.Server.Cookies.Csrf.Secret) | Out-Null
    }

    # on session
    else {
        $WebEvent.Session.Data[$key] = $Secret
    }
}

function New-PodeCsrfToken
{
    param (
        [Parameter()]
        [string]
        $Secret,

        [Parameter()]
        [string]
        $Salt
    )

    # fail if the csrf logic hasn't been defined
    if (Test-IsEmpty $PodeContext.Server.Cookies.Csrf) {
        throw 'CSRF middleware has not been defined'
    }

    # generate a new secret if none supplied
    if (Test-IsEmpty $Secret) {
        $Secret = New-PodeCsrfSecret
    }

    # generate a new salt if none supplied
    if (Test-IsEmpty $Salt) {
        $Salt = (New-PodeSalt -Length 8)
    }

    # return a new token
    return "t:$($Salt).$(Invoke-PodeSHA256Hash -Value "$($Salt)-$($Secret)")"
}
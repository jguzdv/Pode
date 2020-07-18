# From v1.X to v2.X

This is a brief guide on migrating from Pode v1.X to Pode v2.X.

In Pode v2.X the Server got the biggest overhaul with the dropping of HttpListener.

## Server

If you were previously specifying `-Type Pode` on your [`Start-PodeServer`](../../../Functions/Core/Start-PodeServer), then you no longer need to - all servers now default to using Pode new .NET Core socket listener.

### Endpoints

With the dropping of HttpListener, the `-Certificate` parameter is now the old `-CertificateFile` parameter. The `-RawCertificate` parameter has been renamed, and it now called `-X509Certificate`.

The `-CertificateThumbprint` parameter remains the same, and only works on Windows.
The `-Certificate` parameter is now the `-CertificateName` parameter, and also only works on Windows.

### Configuration

Settings that use to be under `Server > Pode` are now just under `Server`. For example, SSL protocols have moved from:

```powershell
@{
    Server = @{
        Pode=  @{
            Ssl= @{
                Protocols = @('TLS', 'TLS11', 'TLS12')
            }
        }
    }
}
```

to:

```powershell
@{
    Server = @{
        Ssl= @{
            Protocols = @('TLS', 'TLS11', 'TLS12')
        }
    }
}
```

### Authentication

Authentication underwent a hefty change in 2.0, with `Get-PodeAuthMiddleware` being removed.

First, `New-PodeAuthType` has been renamed to [`New-PodeAuthScheme`](../../../Functions/Authentication/New-PodeAuthScheme) - with its `-Scheme` parameter also being renamed to `-Type`.

The old `-AutoLogin` (now just `-Login`), and `-Logout` switches, from `Get-PodeAuthMiddleware`, have been moved onto the [`Add-PodeRoute`](../../../Functions/Routes/Add-PodeRoute) function. The [`Add-PodeRoute`](../../../Functions/Routes/Add-PodeRoute) function now also has a new `-Authentication` parameter, which accepts the name of an Auth supplied to [`Add-PodeAuth`](../../../Functions/Authentication/Add-PodeAuth); this will automatically setup authentication middleware for that route.

The old `-Sessionless`, `-FailureUrl`, `-FailureMessage` and `-SuccessUrl` parameters, from `Get-PodeAuthMiddleware`, have all been moved onto the [`Add-PodeAuth`](../../../Functions/Authentication/Add-PodeAuth) function.

The old `-EnabledFlash` switch has been removed (it's just enabled by default if sessions are enabled).

There's also a new [`Add-PodeAuthMiddleware`](../../../Functions/Authentication/Add-PodeAuthMiddleware) function, which will let you setup global authentication middleware.

Furthermore, the OpenAPI functions for `Set-PodeOAAuth` and `Set-PodeOAGlobalAuth` have been removed. The new [`Add-PodeAuthMiddleware`](../../../Functions/Authentication/Add-PodeAuthMiddleware) function and `-Authentication` parameter on [`Add-PodeRoute`](../../../Functions/Routes/Add-PodeRoute) set these up for you automatically in OpenAPI.

### Endpoint and Protocol

On the following functions:

* `Add-PodeRoute`
* `Add-PodeStaticRoute`
* `Get-PodeRoute`
* `Get-PodeStaticRoute`
* `Remove-PodeRoute`
* `Remove-PodeStaticRoute`

The `-Endpoint` and `-Protocol` parameters have been removed in favour of `-EndpointName`.
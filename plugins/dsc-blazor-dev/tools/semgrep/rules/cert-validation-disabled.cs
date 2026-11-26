using System.Net;
using System.Net.Http;
using System.Net.Security;

public static class HttpSetup
{
    public static HttpClient Bad()
    {
        var handler = new HttpClientHandler();
        /// ruleid: dsc-cert-validation-disabled
        handler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => true;
        return new HttpClient(handler);
    }

    public static HttpClient BadInitializer()
    {
        /// ruleid: dsc-cert-validation-disabled
        var handler = new HttpClientHandler { ServerCertificateCustomValidationCallback = (m, c, ch, e) => true };
        return new HttpClient(handler);
    }

    public static HttpClient BadDangerous()
    {
        var handler = new HttpClientHandler
        {
            /// ruleid: dsc-cert-validation-disabled
            ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator
        };
        return new HttpClient(handler);
    }

    public static void BadGlobal()
    {
        /// ruleid: dsc-cert-validation-disabled
        ServicePointManager.ServerCertificateValidationCallback += (sender, cert, chain, errors) => true;
    }

    public static HttpClient Good()
    {
        var handler = new HttpClientHandler();
        /// ok: dsc-cert-validation-disabled
        handler.ServerCertificateCustomValidationCallback = (message, cert, chain, errors) => errors == SslPolicyErrors.None;
        return new HttpClient(handler);
    }
}

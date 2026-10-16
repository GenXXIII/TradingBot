using System.Security.Cryptography;
using System.Text;

namespace AutoScalping.Api;

public sealed class BridgeSecurity(IConfiguration configuration)
{
    private readonly byte[] _expected = Encoding.UTF8.GetBytes(
        configuration["Mt5:BridgeKey"] ?? "local-demo-key-change-me");

    public bool IsAuthorized(HttpRequest request)
    {
        if (!request.Headers.TryGetValue("X-Bot-Key", out var provided))
        {
            return false;
        }

        var actual = Encoding.UTF8.GetBytes(provided.ToString());
        return actual.Length == _expected.Length && CryptographicOperations.FixedTimeEquals(actual, _expected);
    }
}

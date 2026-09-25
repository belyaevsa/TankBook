namespace Tankbook.Admin;

/// <summary>The <c>Admin</c> configuration section.</summary>
public sealed class AdminOptions
{
    /// <summary>
    /// The one-time token that registers the first passkey, from the secret store. Only its
    /// SHA-256 is ever stored; once a passkey exists it registers nothing.
    /// </summary>
    public string BootstrapToken { get; set; } = "";

    /// <summary>A session's absolute lifetime; it does not slide.</summary>
    public int SessionHours { get; set; } = 8;

    /// <summary>Sign-in and registration requests allowed per client address per minute.</summary>
    public int SignInPermitsPerMinute { get; set; } = 10;
}

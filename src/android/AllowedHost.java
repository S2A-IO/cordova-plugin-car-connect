/**
 * AllowedHost – Holds the list of permitted hosts.
 * 
 * Copyright © 2025 RIKSOF. MIT License.
 */
public final class AllowedHost {
    private final String packageName;
    private final String sha256Digest;

    public AllowedHost(String packageName, String sha256Digest) {
        this.packageName   = packageName;
        this.sha256Digest  = sha256Digest;
    }

    public String packageName()   { return packageName;   }
    public String sha256Digest()  { return sha256Digest;  }
}

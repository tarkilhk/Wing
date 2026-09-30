package com.tarkilhk.wing

import org.junit.Assert.*
import org.junit.Test

class ExternalShareUriPolicyTest {
    @Test fun onlyGrantedExternalContentIsAccepted() {
        fun allowed(scheme: String? = "content", authority: String? = "photos.provider",
                    provider: String? = "photos.app", granted: Boolean = true): Boolean =
            ExternalShareUriPolicy.allows(scheme, authority, provider, "com.tarkilhk.wing.dev", granted)
        assertTrue(allowed())
        assertFalse(allowed(scheme = "file"))
        assertFalse(allowed(scheme = "android.resource"))
        assertFalse(allowed(scheme = null))
        assertFalse(allowed(authority = null))
        assertFalse(allowed(authority = ""))
        assertFalse(allowed(authority = "10@photos.provider"))
        assertFalse(allowed(provider = null))
        // Provider ownership, rather than an authority spelling, defines self-owned content.
        assertFalse(allowed(authority = "some.alias", provider = "com.tarkilhk.wing.dev"))
        assertFalse(allowed(granted = false))
    }
}

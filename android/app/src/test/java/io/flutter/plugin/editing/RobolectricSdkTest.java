package io.flutter.plugin.editing;

import java.nio.file.Files;
import java.util.Properties;
import org.junit.Test;
import org.robolectric.annotation.Config;
import org.robolectric.plugins.DefaultSdkProvider;
import org.robolectric.plugins.LegacyDependencyResolver;
import static org.junit.Assert.assertTrue;

/** Tests the Gradle-provisioned SDK without the runtime downloader or Maven cache. */
public class RobolectricSdkTest {
    @Test public void animationTestSdkResolvesOffline() {
        Properties settings = new Properties();
        settings.putAll(System.getProperties());
        settings.setProperty("robolectric.offline", "true");
        var sdks = new DefaultSdkProvider(new LegacyDependencyResolver(settings)).getSdks();
        for (int api : ImeAnimationCacheTest.class.getAnnotation(Config.class).sdk()) {
            var sdk = sdks.stream().filter(candidate -> candidate.getApiLevel() == api)
                .findFirst().orElseThrow();
            assertTrue("Gradle must provision the animation test SDK", Files.isRegularFile(sdk.getJarPath()));
        }
    }
}

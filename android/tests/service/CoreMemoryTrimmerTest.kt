package cc.chenx.flclash.service

import android.content.ComponentCallbacks2
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreMemoryTrimmerTest {
    @Test
    fun `shouldTrimCoreMemory triggers only from running-low and above`() {
        assertFalse(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE))
        assertTrue(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW))
        assertTrue(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL))
        assertTrue(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN))
        assertTrue(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_BACKGROUND))
        assertTrue(shouldTrimCoreMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE))
    }

    @Test
    fun `onTrimMemory ignores events while service is inactive`() {
        var calls = 0
        val trimmer = CoreMemoryTrimmer(
            minIntervalMillis = 30_000L,
            nowMillis = { 100L },
            onTrim = { calls++ },
        )

        assertFalse(trimmer.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE, active = false))
        assertEquals(0, calls)
    }

    @Test
    fun `onTrimMemory throttles repeated pressure callbacks`() {
        var now = 0L
        var calls = 0
        val trimmer = CoreMemoryTrimmer(
            minIntervalMillis = 30_000L,
            nowMillis = { now },
            onTrim = { calls++ },
        )

        assertTrue(trimmer.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW, active = true))
        assertEquals(1, calls)

        now = 29_999L
        assertFalse(trimmer.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_COMPLETE, active = true))
        assertEquals(1, calls)

        now = 30_000L
        assertTrue(trimmer.onTrimMemory(ComponentCallbacks2.TRIM_MEMORY_BACKGROUND, active = true))
        assertEquals(2, calls)
    }
}

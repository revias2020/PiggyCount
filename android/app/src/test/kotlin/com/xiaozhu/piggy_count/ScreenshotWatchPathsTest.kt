package com.xiaozhu.piggy_count

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotWatchPathsTest {
    @Test
    fun normalize_stripsStorageRoot() {
        assertEquals(
            "Pictures/Screenshots",
            ScreenshotWatchPaths.normalize(
                "/storage/emulated/0/Pictures/Screenshots/",
            ),
        )
        assertEquals(
            "DCIM/Screenshots",
            ScreenshotWatchPaths.normalize("/sdcard/DCIM/Screenshots"),
        )
    }

    @Test
    fun normalize_rejectsContentUri() {
        assertNull(
            ScreenshotWatchPaths.normalize(
                "content://com.android.externalstorage.documents/tree/primary%3APictures",
            ),
        )
    }

    @Test
    fun matches_relativeDir() {
        assertTrue(
            ScreenshotWatchPaths.matches(
                "/storage/emulated/0/Pictures/Screenshots/Screenshot_1.jpg",
                listOf("Pictures/Screenshots"),
            ),
        )
        assertFalse(
            ScreenshotWatchPaths.matches(
                "/storage/emulated/0/Pictures/Other/a.jpg",
                listOf("Pictures/Screenshots"),
            ),
        )
    }

    @Test
    fun matches_subdir() {
        assertTrue(
            ScreenshotWatchPaths.matches(
                "/storage/emulated/0/Pictures/Screenshots/edit/a.jpg",
                listOf("Pictures/Screenshots"),
            ),
        )
    }

    @Test
    fun directoryKey_fromRelativePath() {
        assertEquals(
            "Pictures/Screenshots",
            ScreenshotWatchPaths.directoryKey(
                absolutePath = "/storage/emulated/0/Pictures/Screenshots/x.jpg",
                relativePath = "Pictures/Screenshots/",
            ),
        )
    }

    @Test
    fun emptyWatch_neverMatches() {
        assertFalse(
            ScreenshotWatchPaths.matches(
                "/storage/emulated/0/Pictures/Screenshots/x.jpg",
                emptyList(),
            ),
        )
    }
}

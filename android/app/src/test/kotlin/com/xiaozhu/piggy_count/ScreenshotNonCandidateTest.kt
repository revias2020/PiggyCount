package com.xiaozhu.piggy_count

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotNonCandidateTest {
    @Test
    fun liveScreenshot_isCandidate() {
        assertFalse(
            ScreenshotNonCandidate.matches(
                path = "/storage/emulated/0/Pictures/Screenshots/Screenshot_20260828_190635.jpg",
                name = "Screenshot_20260828_190635.jpg",
            ),
        )
    }

    @Test
    fun galleryDeleteEncodedName_isNonCandidate() {
        assertTrue(
            ScreenshotNonCandidate.matches(
                path = "/storage/emulated/0/.trash/something.jpg",
                name = "1787915220947-gallery@delete-07storage08emulated01008Pictures0bScreenshots1eScreenshot_20260828_190635.jpg",
            ),
        )
    }

    @Test
    fun atDeleteInDisplayName_alone_isNonCandidate() {
        assertTrue(
            ScreenshotNonCandidate.matches(
                path = "/storage/emulated/0/Pictures/Screenshots/x.jpg",
                name = "123-vendor@delete-Screenshot_x.jpg",
            ),
        )
    }

    @Test
    fun isTrashedFlag_isNonCandidate() {
        assertTrue(
            ScreenshotNonCandidate.matches(
                path = "/storage/emulated/0/Pictures/Screenshots/Screenshot_x.jpg",
                name = "Screenshot_x.jpg",
                trashed = true,
            ),
        )
    }

    @Test
    fun trashInPath_isNonCandidate() {
        assertTrue(
            ScreenshotNonCandidate.matches(
                path = "/storage/emulated/0/Pictures/.trash/Screenshot_x.jpg",
                name = "Screenshot_x.jpg",
            ),
        )
    }
}

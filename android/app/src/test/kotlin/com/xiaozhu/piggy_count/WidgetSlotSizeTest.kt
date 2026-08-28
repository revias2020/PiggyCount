package com.xiaozhu.piggy_count

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetSlotSizeTest {
    @Test
    fun computeRenderWidthDp_boostsToDesignWidth() {
        assertEquals(364, WidgetSlotSize.computeRenderWidthDp(272, 288))
    }

    @Test
    fun computeRenderWidthDp_usesLargestEstimate() {
        assertEquals(380, WidgetSlotSize.computeRenderWidthDp(272, 380))
    }

    @Test
    fun computeRenderWidthDp_keepsReportedWhenLargest() {
        assertEquals(400, WidgetSlotSize.computeRenderWidthDp(400, 288))
    }

    @Test
    fun pickCandidate_singleReturnsAsIs() {
        assertEquals(272 to 156, WidgetSlotSize.pickCandidate(listOf(272 to 156)))
    }

    @Test
    fun pickCandidate_prefersLargerArea() {
        val pick = WidgetSlotSize.pickCandidate(
            listOf(
                272 to 156,
                364 to 182,
            ),
        )
        assertEquals(364 to 182, pick)
    }

    @Test
    fun pickCandidate_tieBreaksByAspectWhenAreaEqual() {
        val pick = WidgetSlotSize.pickCandidate(
            listOf(
                300 to 150, // aspect 2.0
                320 to 160, // aspect 2.0, larger area
            ),
        )
        assertEquals(320 to 160, pick)
    }
}

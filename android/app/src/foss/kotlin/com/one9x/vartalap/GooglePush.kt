package com.one9x.vartalap

import android.content.Context

/** The foss build has no Google code, so Google push never exists here. */
object GooglePush {
    @Suppress("UNUSED_PARAMETER")
    fun available(context: Context): Boolean = false
}

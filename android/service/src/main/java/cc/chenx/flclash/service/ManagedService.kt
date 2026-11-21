package cc.chenx.flclash.service

import android.app.Service
import android.content.ComponentCallbacks2
import android.os.Build
import android.os.SystemClock
import cc.chenx.flclash.common.BroadcastAction
import cc.chenx.flclash.common.GlobalState
import cc.chenx.flclash.common.sendBroadcast
import cc.chenx.flclash.core.Core
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicLong

const val ACTION_KEEP_ALIVE = "cc.chenx.flclash.service.action.KEEP_ALIVE"

interface ManagedService {
    fun start()

    fun stop()
}

internal fun shouldTrimCoreMemory(level: Int): Boolean =
    level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW

internal class CoreMemoryTrimmer(
    private val minIntervalMillis: Long = 30_000L,
    private val nowMillis: () -> Long = SystemClock::elapsedRealtime,
    private val onTrim: () -> Unit = { GlobalState.launch { Core.forceGC() } },
) {
    private val lastTrimAtMillis = AtomicLong(Long.MIN_VALUE)

    fun onTrimMemory(level: Int, active: Boolean): Boolean {
        if (!active || !shouldTrimCoreMemory(level)) return false
        val now = nowMillis()
        while (true) {
            val prev = lastTrimAtMillis.get()
            if (prev != Long.MIN_VALUE && now - prev < minIntervalMillis) {
                return false
            }
            if (lastTrimAtMillis.compareAndSet(prev, now)) {
                onTrim()
                return true
            }
        }
    }
}

internal fun Service.stopForegroundCompat() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        stopForeground(Service.STOP_FOREGROUND_REMOVE)
    } else {
        @Suppress("DEPRECATION")
        stopForeground(true)
    }
}

internal fun Service.notifyVpnStartRequested() {
    GlobalState.log("VPN start requested")
    BroadcastAction.VPN_START_REQUESTED.sendBroadcast()
}

internal fun Service.notifyVpnRevoked() {
    GlobalState.log("VPN permission revoked")
    BroadcastAction.VPN_REVOKED.sendBroadcast()
}

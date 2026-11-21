package cc.chenx.flclash.service

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import cc.chenx.flclash.core.Core
import cc.chenx.flclash.service.modules.ServiceModules

class ProxyService : Service(), ManagedService {
    private val modules = ServiceModules(this)
    private val memoryTrimmer = CoreMemoryTrimmer()
    private val binder = LocalBinder()

    override fun onDestroy() {
        try {
            cleanup()
        } finally {
            super.onDestroy()
        }
    }

    override fun onLowMemory() {
        if (modules.isStarted) {
            Core.forceGC()
        }
        super.onLowMemory()
    }

    override fun onTrimMemory(level: Int) {
        memoryTrimmer.onTrimMemory(level, active = modules.isStarted)
        super.onTrimMemory(level)
    }

    inner class LocalBinder : Binder() {
        val service: ProxyService
            get() = this@ProxyService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        modules.ensureForeground()
        if (intent?.action != ACTION_KEEP_ALIVE) {
            notifyVpnStartRequested()
        }
        return START_STICKY
    }

    override fun start() {
        try {
            modules.start()
        } catch (error: Exception) {
            stop()
            throw error
        }
    }

    override fun stop() {
        try {
            cleanup()
        } finally {
            stopSelf()
        }
    }

    private fun cleanup() = modules.stop()
}

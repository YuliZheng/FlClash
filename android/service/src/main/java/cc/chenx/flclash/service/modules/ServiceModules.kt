package cc.chenx.flclash.service.modules

import android.app.Service
import cc.chenx.flclash.service.stopForegroundCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

internal interface ServiceModule {
    fun start()

    fun stop()
}

internal class ServiceModules(private val service: Service) {
    private var scope: CoroutineScope? = null
    private var modules = emptyList<ServiceModule>()

    @Volatile
    private var started = false

    @Volatile
    private var foregroundPromoted = false

    val isStarted: Boolean
        get() = started

    @Synchronized
    fun ensureForeground() {
        val notificationModule = modules.filterIsInstance<NotificationModule>().firstOrNull()
        if (notificationModule != null) {
            notificationModule.ensureForeground()
        } else {
            promoteServiceForeground(service)
        }
        foregroundPromoted = true
    }

    @Synchronized
    fun start() {
        if (scope != null) return

        val nextScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val nextModules = listOf(
            NotificationModule(service, nextScope),
            NetworkObserveModule(service),
        )
        val startedModules = mutableListOf<ServiceModule>()

        try {
            nextModules.forEach { module ->
                module.start()
                startedModules.add(module)
            }
            scope = nextScope
            modules = nextModules
            started = true
            foregroundPromoted = true
        } catch (error: Throwable) {
            nextScope.cancel()
            startedModules.asReversed().forEach { module ->
                runCatching { module.stop() }
            }
            if (foregroundPromoted) {
                foregroundPromoted = false
                service.stopForegroundCompat()
            }
            throw error
        }
    }

    @Synchronized
    fun stop() {
        val currentScope = scope
        if (currentScope == null) {
            if (foregroundPromoted) {
                foregroundPromoted = false
                service.stopForegroundCompat()
            }
            return
        }
        val currentModules = modules
        scope = null
        modules = emptyList()
        started = false
        foregroundPromoted = false

        currentScope.cancel()
        currentModules.asReversed().forEach { module ->
            runCatching { module.stop() }
        }
    }
}

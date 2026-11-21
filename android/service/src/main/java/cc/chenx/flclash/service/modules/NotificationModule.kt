package cc.chenx.flclash.service.modules

import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.getSystemService
import cc.chenx.flclash.common.Components
import cc.chenx.flclash.common.GlobalState
import cc.chenx.flclash.common.QuickAction
import cc.chenx.flclash.common.quickIntent
import cc.chenx.flclash.common.receiveBroadcastFlow
import cc.chenx.flclash.common.startForeground
import cc.chenx.flclash.common.toPendingIntent
import cc.chenx.flclash.core.Core
import cc.chenx.flclash.service.R
import cc.chenx.flclash.service.ServiceConfig
import cc.chenx.flclash.service.models.NotificationParams
import cc.chenx.flclash.service.models.getSpeedTrafficText
import cc.chenx.flclash.service.stopForegroundCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

private data class ExtendedNotificationParams(
    val title: String,
    val stopText: String,
    val showStopAction: Boolean,
    val contentText: String,
)

private fun NotificationParams.extended(service: Service) =
    ExtendedNotificationParams(
        title,
        service.getString(R.string.stop),
        showStopAction,
        if (networkSpeedNotification) {
            Core.getSpeedTrafficText(onlyStatisticsProxy)
        } else {
            service.getString(R.string.connected)
        },
    )

private fun createNotificationBuilder(service: Service): NotificationCompat.Builder {
    val intent = Intent().setComponent(Components.mainActivity)

    return NotificationCompat.Builder(
        service,
        GlobalState.NOTIFICATION_CHANNEL,
    ).apply {
        setSmallIcon(R.drawable.ic_service)
        setContentTitle("FlClash")
        setContentIntent(intent.toPendingIntent)
        setPriority(NotificationCompat.PRIORITY_LOW)
        setCategory(NotificationCompat.CATEGORY_SERVICE)
        setOngoing(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
        }
        setShowWhen(true)
        setOnlyAlertOnce(true)
    }
}

private fun startForegroundWithParams(
    service: Service,
    builder: NotificationCompat.Builder,
    params: ExtendedNotificationParams,
) {
    service.startForeground(
        with(builder) {
            setContentTitle(params.title)
            setContentText(params.contentText)
            clearActions()
            if (params.showStopAction) {
                addAction(
                    0,
                    params.stopText,
                    QuickAction.STOP.quickIntent.toPendingIntent,
                )
            }
            build()
        },
    )
}

internal fun promoteServiceForeground(service: Service) {
    val params = ServiceConfig.notificationParams.value
        .copy(networkSpeedNotification = false)
        .extended(service)
    startForegroundWithParams(service, createNotificationBuilder(service), params)
}

internal class NotificationModule(
    private val service: Service,
    private val scope: CoroutineScope,
) : ServiceModule {
    @Volatile
    private var currentParams: ExtendedNotificationParams? = null

    override fun start() {
        val initialParams = ServiceConfig.notificationParams.value.extended(service)
        update(initialParams)
        scope.launch {
            var displayedParams = initialParams
            val screenFlow = service.receiveBroadcastFlow {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }.map { intent ->
                intent.action == Intent.ACTION_SCREEN_ON
            }.onStart {
                emit(isScreenOn())
            }

            combine(
                ServiceConfig.notificationParams,
                screenFlow,
            ) { params, screenOn ->
                params to screenOn
            }.collectLatest { (params, screenOn) ->
                if (!screenOn) return@collectLatest

                if (!params.networkSpeedNotification) {
                    val nextParams = params.extended(service)
                    if (nextParams != displayedParams) {
                        update(nextParams)
                        displayedParams = nextParams
                    }
                    return@collectLatest
                }

                while (true) {
                    delay(1_000)
                    val nextParams = params.extended(service)
                    if (nextParams != displayedParams) {
                        update(nextParams)
                        displayedParams = nextParams
                    }
                }
            }
        }
    }

    fun ensureForeground() {
        val params = currentParams ?: ServiceConfig.notificationParams.value
            .copy(networkSpeedNotification = false)
            .extended(service)
        update(params)
    }

    private fun isScreenOn() =
        service.getSystemService<PowerManager>()?.isInteractive ?: true

    private val notificationBuilder: NotificationCompat.Builder by lazy {
        createNotificationBuilder(service)
    }

    private fun update(params: ExtendedNotificationParams) {
        synchronized(notificationBuilder) {
            currentParams = params
            startForegroundWithParams(service, notificationBuilder, params)
        }
    }

    override fun stop() {
        currentParams = null
        service.stopForegroundCompat()
    }
}

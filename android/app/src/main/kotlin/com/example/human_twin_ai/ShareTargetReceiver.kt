package com.example.human_twin_ai

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build

/** Receives the Android chooser's "target chosen" callback (Android reports the chosen component). */
class ShareTargetReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        chosen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT, ComponentName::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT)
        }
    }

    companion object {
        @Volatile
        var chosen: ComponentName? = null
    }
}

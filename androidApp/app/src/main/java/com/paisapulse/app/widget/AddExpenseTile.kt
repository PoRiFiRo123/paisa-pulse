package com.paisapulse.app.widget

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.paisapulse.app.MainActivity

/** Quick Settings tile "Add Expense": opens Quick Add, like the iPhone's Control Center / Action Button control. */
class AddExpenseTile : TileService() {
  override fun onStartListening() {
    qsTile?.apply { state = Tile.STATE_INACTIVE; label = "Add Expense"; updateTile() }
  }

  @SuppressLint("StartActivityAndCollapseDeprecated")
  override fun onClick() {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("paisapulse://add?type=expense"), this, MainActivity::class.java)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val open = {
      if (Build.VERSION.SDK_INT >= 34) startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
      else @Suppress("DEPRECATION") startActivityAndCollapse(intent)
    }
    if (isLocked) unlockAndRun { open() } else open()
  }
}

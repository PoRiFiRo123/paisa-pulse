package com.paisapulse.app

import android.app.Application
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.data.Store
import com.paisapulse.app.work.Seed
import com.paisapulse.app.work.Services

class PaisaApp : Application() {
  override fun onCreate() {
    super.onCreate()
    Store.init(this); Prefs.init(this)
    Services.init(this)
    com.paisapulse.app.cloud.Cloud.init(this)
    com.paisapulse.app.ui.Celebrations.init(this)
    Seed.ensureCategories()
  }
}

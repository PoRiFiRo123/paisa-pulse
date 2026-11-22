package com.paisapulse.app.work

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.paisapulse.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URL

/** Software Update: CI publishes each build as GitHub Release "build-<n>" with PaisaPulse.apk. */
object Updates {
  data class Available(val build: Int, val apk: String?, val page: String)
  var available by mutableStateOf<Available?>(null)

  suspend fun check(): Boolean = withContext(Dispatchers.IO) {
    if (BuildConfig.VERSION_CODE <= 1) return@withContext false
    runCatching {
      val o = Json.parseToJsonElement(URL("https://api.github.com/repos/${BuildConfig.RELEASE_REPO}/releases/latest").readText()).jsonObject
      val n = o["tag_name"]!!.jsonPrimitive.content.removePrefix("build-").toInt()
      val apk = o["assets"]!!.jsonArray.map { it.jsonObject }.firstOrNull { it["name"]!!.jsonPrimitive.content.endsWith(".apk") }?.get("browser_download_url")?.jsonPrimitive?.content
      available = if (n > BuildConfig.VERSION_CODE) Available(n, apk, o["html_url"]!!.jsonPrimitive.content) else null
      available != null
    }.getOrDefault(false)
  }
}

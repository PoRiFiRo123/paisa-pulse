package com.paisapulse.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.mutableStateOf
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.paisapulse.app.data.Prefs
import com.paisapulse.app.ui.PaisaTheme
import com.paisapulse.app.ui.Root
import com.paisapulse.app.ui.Tab
import com.paisapulse.app.ui.Ui
import com.paisapulse.app.work.Demo
import com.paisapulse.app.work.Services

class MainActivity : FragmentActivity() {
  private val locked = mutableStateOf(false)

  override fun onCreate(savedInstanceState: Bundle?) {
    enableEdgeToEdge()
    super.onCreate(savedInstanceState)
    // Screenshot automation (CI): --ez PaisaDemo true --es PaisaTab activity --ez PaisaAdd true
    if (intent.getBooleanExtra("PaisaDemo", false)) Demo.seed()
    intent.getStringExtra("PaisaTab")?.let { t -> Ui.tab = Tab.entries.firstOrNull { it.name.equals(t, true) } ?: Tab.Home }
    if (intent.getBooleanExtra("PaisaAdd", false)) Ui.sheet = com.paisapulse.app.ui.Sheet.Add()
    Ui.handle(intent?.data)
    locked.value = Prefs.appLock
    setContent { PaisaTheme { Root(locked.value) { authenticate() } } }
    if (locked.value) authenticate()
  }

  override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); Ui.handle(intent.data) }

  override fun onStart() { super.onStart(); Services.runMaintenance() }

  override fun onStop() { super.onStop(); if (Prefs.appLock) locked.value = true }

  override fun onResume() { super.onResume(); if (locked.value) authenticate() }

  private fun authenticate() {
    val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
      override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) { locked.value = false }
    })
    runCatching {
      prompt.authenticate(BiometricPrompt.PromptInfo.Builder().setTitle("Unlock Paisa Pulse").setAllowedAuthenticators(BIOMETRIC_WEAK or DEVICE_CREDENTIAL).build())
    }.onFailure { locked.value = false }
  }
}

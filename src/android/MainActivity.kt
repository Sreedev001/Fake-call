package com.example.contact_book

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.provider.ContactsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// NOTE: the first line (package ...) is rewritten by the CI workflow to match
// the generated project. Keep it as the very first line of this file.
class MainActivity : FlutterActivity() {
    private val channelName = "contact_book/native"
    private val permRequestCode = 4201
    private var pendingPermResult: MethodChannel.Result? = null
    private var proximityLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasContactsPermission" -> result.success(hasContactsPermission())

                    "requestContactsPermission" -> {
                        if (hasContactsPermission()) {
                            result.success(true)
                        } else {
                            pendingPermResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.READ_CONTACTS),
                                permRequestCode
                            )
                        }
                    }

                    "getContacts" -> {
                        Thread {
                            val list = try {
                                readContacts()
                            } catch (e: Exception) {
                                ArrayList<HashMap<String, String>>()
                            }
                            runOnUiThread { result.success(list) }
                        }.start()
                    }

                    "setProximityScreenOff" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        result.success(setProximity(on))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hasContactsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 23) return true
        return checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermResult?.success(granted)
            pendingPermResult = null
        }
    }

    private fun readContacts(): ArrayList<HashMap<String, String>> {
        val out = ArrayList<HashMap<String, String>>()
        val seen = HashSet<String>()
        val cursor = contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER
            ),
            null,
            null,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " COLLATE LOCALIZED ASC"
        )
        cursor?.use {
            val idIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val nameIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            val numIdx = it.getColumnIndex(ContactsContract.CommonDataKinds.Phone.NUMBER)
            while (it.moveToNext()) {
                val id = it.getString(idIdx) ?: continue
                if (!seen.add(id)) continue
                val name = it.getString(nameIdx) ?: continue
                val number = it.getString(numIdx) ?: ""
                out.add(hashMapOf("name" to name, "number" to number))
            }
        }
        return out
    }

    /** Turns the screen off when the phone is held to the ear (like the real dialer). */
    private fun setProximity(on: Boolean): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        if (on) {
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) {
                return false
            }
            if (proximityLock == null) {
                proximityLock = pm.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "contactbook:proximity"
                )
                proximityLock?.setReferenceCounted(false)
            }
            proximityLock?.let { if (!it.isHeld) it.acquire() }
            return true
        } else {
            proximityLock?.let { if (it.isHeld) it.release() }
            return true
        }
    }

    override fun onDestroy() {
        setProximity(false)
        super.onDestroy()
    }
}

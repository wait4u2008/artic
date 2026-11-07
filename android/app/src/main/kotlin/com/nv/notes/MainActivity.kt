package com.nv.notes

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE: block screenshots and hide content in the recent-apps
        // preview, so file names/content never leak through the system UI.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}

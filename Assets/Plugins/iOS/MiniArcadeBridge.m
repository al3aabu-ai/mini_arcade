#import <Foundation/Foundation.h>

// Unity (il2cpp) calls MiniArcade_UnityToHost via [DllImport("__Internal")]. That symbol
// MUST be defined HERE, inside UnityFramework, so il2cpp resolves it in-image at the
// framework's own link step. (Leaving it undefined and resolving from the host via
// `-undefined dynamic_lookup` crashes on iOS: EXC_BAD_ACCESS / CODESIGNING "Invalid Page".)
//
// Unity builds the framework with -fvisibility=hidden + dead-stripping, so BOTH functions
// need visibility("default") to be exported (the host links MiniArcade_SetHostCallback) and
// used to survive dead-stripping (SetHostCallback is unreferenced inside the framework).

static void (*g_hostCallback)(const char *) = NULL;

// Called by the host (UnityEmbed) once, after Unity loads, to register where messages go.
__attribute__((visibility("default"), used))
void MiniArcade_SetHostCallback(void (*cb)(const char *)) {
    g_hostCallback = cb;
}

// Called by Unity C# (UnityBridge.SendToHost). Forwards to the host if registered.
__attribute__((visibility("default"), used))
void MiniArcade_UnityToHost(const char *message) {
    if (g_hostCallback != NULL) {
        g_hostCallback(message);
    }
}

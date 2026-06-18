using System;
using UnityEngine;

namespace MiniArcade.Core
{
    /// <summary>
    /// Minimal state machine for <see cref="AppState"/>. Concrete per-state
    /// behaviour is layered on in later milestones; for now this owns the
    /// current state and broadcasts transitions.
    /// </summary>
    public class GameStateMachine
    {
        public AppState Current { get; private set; } = AppState.Boot;

        /// <summary>Raised after a successful transition. Args are (from, to).</summary>
        public event Action<AppState, AppState> StateChanged;

        public void Set(AppState next)
        {
            if (next == Current)
                return;

            AppState previous = Current;
            Current = next;
            Debug.Log($"[StateMachine] {previous} -> {next}");
            StateChanged?.Invoke(previous, next);
        }
    }
}

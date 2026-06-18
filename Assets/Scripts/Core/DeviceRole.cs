namespace MiniArcade.Core
{
    /// <summary>
    /// What role this physical device plays in a session. The Host renders the
    /// public "TV" view (via an external display) AND shows a private
    /// master-control UI on its own screen (spec sections 3 & 4).
    /// </summary>
    public enum DeviceRole
    {
        Undecided,
        Host,        // Runs the authoritative session + drives the TV output
        Controller   // A player's phone acting as a private controller
    }
}

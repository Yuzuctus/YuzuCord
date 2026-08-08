using System.Windows;
using System.Windows.Media;

namespace RandomFavorites.Setup;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        if (SystemParameters.HighContrast)
            ApplyHighContrastPalette();

        base.OnStartup(e);
    }

    private void ApplyHighContrastPalette()
    {
        Resources["WindowBackground"] = SystemColors.WindowBrush;
        Resources["Surface"] = SystemColors.WindowBrush;
        Resources["SurfaceHover"] = SystemColors.ControlBrush;
        Resources["SurfaceRaised"] = SystemColors.WindowBrush;
        Resources["ArtworkSurface"] = SystemColors.WindowBrush;
        Resources["ArtworkShape"] = SystemColors.ControlBrush;
        Resources["BorderSubtle"] = SystemColors.WindowTextBrush;
        Resources["BorderStrong"] = SystemColors.WindowTextBrush;
        Resources["TextPrimary"] = SystemColors.WindowTextBrush;
        Resources["TextSecondary"] = SystemColors.WindowTextBrush;
        Resources["TextQuiet"] = SystemColors.WindowTextBrush;
        Resources["TextDisabled"] = SystemColors.GrayTextBrush;
        Resources["Accent"] = SystemColors.HighlightBrush;
        Resources["AccentHover"] = SystemColors.HighlightBrush;
        Resources["AccentPressed"] = SystemColors.HotTrackBrush;
        Resources["AccentInk"] = SystemColors.HighlightTextBrush;
        Resources["AccentSurface"] = SystemColors.WindowBrush;
        Resources["Error"] = SystemColors.WindowTextBrush;
        Resources["ErrorSurface"] = SystemColors.WindowBrush;
        Resources["Warning"] = SystemColors.WindowTextBrush;
        Resources["WarningSurface"] = SystemColors.WindowBrush;
        Resources["SuccessSurface"] = SystemColors.WindowBrush;

        // Decorative accent colors are removed so they cannot compete with controls.
        Resources["YuzuLemon"] = Brushes.Transparent;
        Resources["YuzuBlue"] = Brushes.Transparent;
        Resources["YuzuBlush"] = Brushes.Transparent;
    }
}

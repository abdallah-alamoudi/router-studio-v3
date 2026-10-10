using System.IO;
using System.Windows;
using Microsoft.Win32;
using RouterStudio.Desktop.Presentation;
namespace RouterStudio.Desktop;
public static class ThemeManager {
 public static void Apply(ThemePreference preference) {
  var name=SystemParameters.HighContrast ? "HighContrast" : preference==ThemePreference.Dark ? "Dark" : preference==ThemePreference.Light ? "Light" : SystemTheme();
  var resources=Application.Current.Resources.MergedDictionaries;
  for(var i=resources.Count-1;i>=0;i--) if(resources[i].Source?.OriginalString.Contains("Resources/Themes/",StringComparison.Ordinal)==true) resources.RemoveAt(i);
  resources.Add(new ResourceDictionary { Source=new Uri($"pack://application:,,,/RouterStudio.Desktop;component/Resources/Themes/{name}.xaml") });
 }
 private static string SystemTheme() {
  try {return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize","AppsUseLightTheme",1) is int value && value==0 ? "Dark" : "Light";}
  catch(Exception ex) when(ex is IOException or UnauthorizedAccessException or System.Security.SecurityException) {return "Light";}
 }
}

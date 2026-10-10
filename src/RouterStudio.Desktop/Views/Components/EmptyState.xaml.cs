using System.Windows;
using System.Windows.Controls;
namespace RouterStudio.Desktop.Views.Components;
public partial class EmptyState : UserControl {
 public EmptyState(){InitializeComponent();}
 public static readonly DependencyProperty TitleProperty=DependencyProperty.Register(nameof(Title),typeof(string),typeof(EmptyState),new PropertyMetadata(""));
 public static readonly DependencyProperty DescriptionProperty=DependencyProperty.Register(nameof(Description),typeof(string),typeof(EmptyState),new PropertyMetadata(""));
 public static readonly DependencyProperty NextStepProperty=DependencyProperty.Register(nameof(NextStep),typeof(string),typeof(EmptyState),new PropertyMetadata(""));
 public string Title {get=>(string)GetValue(TitleProperty);set=>SetValue(TitleProperty,value);}
 public string Description {get=>(string)GetValue(DescriptionProperty);set=>SetValue(DescriptionProperty,value);}
 public string NextStep {get=>(string)GetValue(NextStepProperty);set=>SetValue(NextStepProperty,value);}
}

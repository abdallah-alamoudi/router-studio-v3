using System.Windows;
namespace RouterStudio.Desktop.Views.Components;
public partial class ConfirmationDialog : Window { public ConfirmationDialog(string title,string description){InitializeComponent();Title=title;Heading.Text=title;Explanation.Text=description;Loaded+=(_,_)=>CancelButton.Focus();} private void Confirm(object sender,RoutedEventArgs e){DialogResult=true;} }

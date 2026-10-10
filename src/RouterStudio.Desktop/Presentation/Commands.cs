using System.Windows.Input;
namespace RouterStudio.Desktop.Presentation;
public sealed class DelegateCommand(Action<object?> execute,Func<bool>? canExecute=null) : ICommand {
 public event EventHandler? CanExecuteChanged;
 public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
 public void Execute(object? parameter) { if(CanExecute(parameter)) execute(parameter); }
 public void NotifyCanExecuteChanged() => CanExecuteChanged?.Invoke(this,EventArgs.Empty);
}
public sealed class AsyncCommand(Func<Task> execute,Func<bool>? canExecute=null) : ICommand {
 private bool running;
 public event EventHandler? CanExecuteChanged;
 public bool CanExecute(object? parameter) => !running && (canExecute?.Invoke() ?? true);
 public async void Execute(object? parameter) { await ExecuteAsync(); }
 public async Task ExecuteAsync() {
  if(!CanExecute(null)) return;
  running=true; NotifyCanExecuteChanged();
  try { await execute(); } finally { running=false; NotifyCanExecuteChanged(); }
 }
 public void NotifyCanExecuteChanged() => CanExecuteChanged?.Invoke(this,EventArgs.Empty);
}

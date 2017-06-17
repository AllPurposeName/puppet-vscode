import net = require('net');
import path = require('path');
import vscode = require('vscode');
import cp = require('child_process');
import { LanguageClient, LanguageClientOptions, ServerOptions } from 'vscode-languageclient';
import { setupPuppetCommands } from '../src/puppetcommands';
import * as messages from '../src/messages';

const langID = 'puppet'; // don't change this

export enum ConnectionStatus {
  NotStarted,
  Starting,
  Running,
  Stopping,
  Failed
}

export enum ConnectionType {
  Unknown,
  Local,
  Remote
}

export interface IConnectionConfiguration {
  type: ConnectionType;
  host: string;
  port: number;
  stopOnClientExit: string;
  timeout: string;
  preLoadPuppet: string;
}

export interface IConnectionManager {
  status: ConnectionStatus;
  languageClient: LanguageClient;
}

export class ConnectionManager implements IConnectionManager {
  private connectionStatus: ConnectionStatus;
  private statusBarItem: vscode.StatusBarItem;
  private connectionConfiguration: IConnectionConfiguration;
  private languageServerClient: LanguageClient = undefined;
  private languageServerProcess = undefined;
  private puppetOutputChannel = undefined;
  private extensionContext = undefined;
  private commandsRegistered = false;

  public get status() : ConnectionStatus {
    return this.connectionStatus;
  }
  public get languageClient() : LanguageClient {
    return this.languageServerClient;
  }

  constructor(context: vscode.ExtensionContext) {
    this.puppetOutputChannel = vscode.window.createOutputChannel('Puppet');
    
    this.extensionContext = context;
  }

  public start(connectionConfig: IConnectionConfiguration) {
    // Setup the configuration
    this.connectionConfiguration = connectionConfig;
    this.connectionConfiguration.type = ConnectionType.Unknown;
    var contextPath = this.extensionContext.asAbsolutePath(path.join('vendor', 'languageserver', 'puppet-languageserver'));

    if (!this.commandsRegistered) {
      this.puppetOutputChannel.appendLine('Configuring commands');
      console.log('Configuring commands');

      setupPuppetCommands(langID, this, this.extensionContext);
      this.commandsRegistered = true;
    }

    this.createStatusBarItem();

    if (this.connectionConfiguration.host == '127.0.0.1' ||
        this.connectionConfiguration.host == 'localhost' ||
        this.connectionConfiguration.host == '') {
      this.connectionConfiguration.type = ConnectionType.Local
    } else {
      this.connectionConfiguration.type = ConnectionType.Remote
    }

    this.languageServerClient = undefined
    this.languageServerProcess = undefined
    this.setConnectionStatus("Starting Puppet...", ConnectionStatus.Starting);

    if (this.connectionConfiguration.type == ConnectionType.Local) {
      this.languageServerProcess = this.createLanguageServerProcess(contextPath, this.puppetOutputChannel);
      if (this.languageServerProcess == undefined) { throw new Error('Unable to start the server process'); }

      this.languageServerProcess.stdout.on('data', (data) => {
        console.log("OUTPUT: " + data.toString());
        this.puppetOutputChannel.appendLine("OUTPUT: " + data.toString());

        // If the language client isn't already running and it's sent the trigger text, start up a client
        if ( (this.languageServerClient == undefined) && (data.toString().match("LANGUAGE SERVER RUNNING") != null) ) {
          this.languageServerClient = this.startLangClientTCP();
          this.extensionContext.subscriptions.push(this.languageServerClient.start());
        }
      });

      this.languageServerProcess.on('close', (exitCode) => {
        console.log("SERVER terminated with exit code: " + exitCode);
        this.puppetOutputChannel.appendLine("SERVER terminated with exit code: " + exitCode);
      });
    }
    else {
      this.languageServerClient = this.startLangClientTCP();
      this.extensionContext.subscriptions.push(this.languageServerClient.start());
    }

    console.log('Congratulations, your extension "vscode-puppet" is now active!');
    this.puppetOutputChannel.appendLine('Congratulations, your extension "vscode-puppet" is now active!');
  }

  public stop() {
    console.log('Stopping...');
    this.puppetOutputChannel.appendLine('Stopping...')

    if (this.connectionStatus === ConnectionStatus.Failed) {
      this.languageServerClient = undefined;
      this.languageServerProcess = undefined;
    }

    this.connectionStatus = ConnectionStatus.Stopping;

    // Close the language server client
    if (this.languageServerClient !== undefined) {
        this.languageServerClient.stop();
        this.languageServerClient = undefined;
    }

    // Kill the language server process we spawned
    if (this.languageServerProcess !== undefined) {
      // Terminate Language Server process
      // TODO: May not be functional on Windows.
      //       Perhaps send the exit command and wait for process to exit?
      this.languageServerProcess.kill();
      this.languageServerProcess = undefined;
    }

    this.connectionStatus = ConnectionStatus.NotStarted;
    
    console.log('Stopped');
    this.puppetOutputChannel.appendLine('Stopped');
  }

  public dispose() : void {
    console.log('Disposing...');
    this.puppetOutputChannel.appendLine('Disposing...');
    // Stop the current session
    this.stop();

    // Dispose of any subscriptions
    this.extensionContext.subscriptions.forEach(item => { item.dispose(); });
    this.extensionContext.subscriptions.clear();
  }

  private createLanguageServerProcess(serverExe: string, myOutputChannel: vscode.OutputChannel) {
    myOutputChannel.appendLine('Language server found at: ' + serverExe)

    let cmd = '';
    let args = [serverExe];
    let options = {};

    // type Platform = 'aix'
    //               | 'android'
    //               | 'darwin'
    //               | 'freebsd'
    //               | 'linux'
    //               | 'openbsd'
    //               | 'sunos'
    //               | 'win32';
    switch (process.platform) {
      case 'win32':
        myOutputChannel.appendLine('Windows spawn process does not work at the moment')
        vscode.window.showErrorMessage('Windows spawn process does not work at the moment. Functionality will be limited to syntax highlighting');
        break;
      default:
        myOutputChannel.appendLine('Starting language server')
        cmd = 'ruby'
        options = {
          shell: true,
          env: process.env,
          stdio: 'pipe',
        };
    }

    console.log("Starting the language server with " + cmd + " " + args.join(" "));
    var proc = cp.spawn(cmd, args, options)
    console.log("ProcID = " + proc.pid);
    myOutputChannel.appendLine('Language server PID:' + proc.pid)

    return proc;
  }

  private startLangClientTCP(): LanguageClient {
    this.puppetOutputChannel.appendLine('Configuring language server options')

    var connMgr:ConnectionManager = this;
    let serverOptions: ServerOptions = function () {
      return new Promise((resolve, reject) => {
        var client = new net.Socket();
        client.connect(connMgr.connectionConfiguration.port, connMgr.connectionConfiguration.host, function () {
          resolve({ reader: client, writer: client });
        });
        client.on('error', function (err) {
          console.log(`[Puppet Lang Server Client] ` + err);
          connMgr.setSessionFailure("Could not start language client: ", err.message);
          
          return null;
        })
      });
    }

    this.puppetOutputChannel.appendLine('Configuring language server client options')
    let clientOptions: LanguageClientOptions = {
      documentSelector: [langID],
    }

    this.puppetOutputChannel.appendLine(`Starting language server client (host ${this.connectionConfiguration.host} port ${this.connectionConfiguration.port})`)
    var title = `tcp lang server (host ${this.connectionConfiguration.host} port ${this.connectionConfiguration.port})`;
    var languageServerClient = new LanguageClient(title, serverOptions, clientOptions)
    languageServerClient.onReady().then(() => {
      this.puppetOutputChannel.appendLine('Language server client started, setting puppet version')
      languageServerClient.sendRequest(messages.PuppetVersionRequest.type).then((versionDetails) => {
        this.setConnectionStatus(versionDetails.puppetVersion, ConnectionStatus.Running);
      });
    }, (reason) => {
      this.setSessionFailure("Could not start language service: ", reason);
    });

    return languageServerClient;
  }

  private restartConnection(connectionConfig?: IConnectionConfiguration) {
      this.stop();
      this.start(connectionConfig);
  }

  private createStatusBarItem() {
    if (this.statusBarItem === undefined) {
      this.statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 1);

      // TODO: Add a command here to show the connection menu
      // this.statusBarItem.command = this.ShowConnectionMenuCommandName;
      this.statusBarItem.show();
      vscode.window.onDidChangeActiveTextEditor(textEditor => {
        if (textEditor === undefined || textEditor.document.languageId !== "puppet") {
          this.statusBarItem.hide();
        }
        else {
          this.statusBarItem.show();
        }
      })
    }
  }

  private setConnectionStatus(statusText: string, status: ConnectionStatus): void {
    // Set color and icon for 'Running' by default
    var statusIconText = "$(terminal) ";
    var statusColor = "#affc74";

    if (status == ConnectionStatus.Starting) {
      statusIconText = "$(sync) ";
      statusColor = "#f3fc74";
    }
    else if (status == ConnectionStatus.Failed) {
      statusIconText = "$(alert) ";
      statusColor = "#fcc174";
    }

    this.connectionStatus = status;
    this.statusBarItem.color = statusColor;
    this.statusBarItem.text = statusIconText + statusText;
  }

  private setSessionFailure(message: string, ...additionalMessages: string[]) {
    this.setConnectionStatus("Starting Error", ConnectionStatus.Failed);
  }
}

unit frmMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.Buttons, ShellAPI,
  System.StrUtils, System.RegularExpressions;

type
  TDownloadResult = record
    Success: Boolean;
    Message: string;
    FileNames: TStringList;
  end;

type
  TForm1 = class(TForm)
    btnDownload: TBitBtn;
    txtYoutubeUrl: TEdit;
    Memo1: TMemo;
    mmLang: TMemo;
    chkforChatbot: TCheckBox;
    BitBtn1: TBitBtn;
    procedure btnDownloadClick(Sender: TObject);
    procedure BitBtn1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}



procedure CleanSubtitleFile_FormatSentences(const InputFile, OutputFile: string);
var
  SLIn, SLOut: TStringList;
  Line, LastLine, Sentence: string;
  I, TempInt: Integer;
begin
  SLIn := TStringList.Create;
  SLOut := TStringList.Create;
  try
    SLIn.LoadFromFile(InputFile);
    LastLine := '';

    for I := 0 to SLIn.Count - 1 do
    begin
      Line := Trim(SLIn[I]);

      // Sayý ya da zaman satýrýysa atla
      if (Line = '') or TryStrToInt(Line, TempInt) or (Pos('-->', Line) > 0) then
        Continue;

      // Aynýysa atla
      if Line = LastLine then
        Continue;

      // Noktadan sonra satýr bölme iþlemi
      Sentence := StringReplace(Line, '. ', '.' + sLineBreak, [rfReplaceAll]);
      SLOut.Add(Sentence);

      LastLine := Line;
    end;

    SLOut.SaveToFile(OutputFile);
  finally
    SLIn.Free;
    SLOut.Free;
  end;
end;


function validateYoutubeUrl(const URL: string): Boolean;
const
  YouTubeUrlRegExp =
    '(?P<YouTubeURL>(?P<Protocol>(?:https?:)?\/\/)?(?P<Subdomain>(?:www|m)\.)?(?P<Domain>(?:youtube\.com|youtu.be))(?P<Path>\/(?:[\w\-]+\?v=|embed\/|v\/)?)(?P<VideoID>[a-zA-Z0-9_-]{11})+)';
var
  RegEx: TRegEx;
  Match: TMatch;
begin
  RegEx := TRegEx.Create(YouTubeUrlRegExp, [roIgnoreCase]);
  Match := RegEx.Match(URL);
  Result := Match.Success;
end;

function DownloadSubtitle(const VideoURL: string;
  const Languages: array of string): TDownloadResult;
var
  ExecInfo: TShellExecuteInfo;
  ExitCode: DWORD;
  CmdLine, LangStr: string;
  SubtitlesPath: string;
  i: Integer;
  SearchRec: TSearchRec;
begin
  ZeroMemory(@ExecInfo, SizeOf(ExecInfo));
  ExecInfo.cbSize := SizeOf(ExecInfo);

  SubtitlesPath := ExtractFilePath(ParamStr(0)) + 'Downloads\Subtitles';
  ForceDirectories(SubtitlesPath);

  LangStr := '';
  for i := Low(Languages) to High(Languages) do
  begin
    if i > Low(Languages) then
      LangStr := LangStr + ',';
    LangStr := LangStr + Languages[i];
  end;

  if LangStr = '' then
    LangStr := 'tr,en';

  CmdLine := Format(
    'Tools\yt-dlp.exe --write-sub --write-auto-sub --convert-subs srt --skip-download --sub-lang %s -o "%s\%%(title)s.%%(ext)s" "%s"',
    [LangStr, SubtitlesPath, VideoURL]);

  with ExecInfo do
  begin
    fMask := SEE_MASK_NOCLOSEPROCESS;
    lpVerb := 'open';
    lpFile := 'cmd.exe';
    lpParameters := PChar('/c ' + CmdLine);
    nShow := SW_HIDE;
  end;

  Result.FileNames := TStringList.Create;

  try
    if ShellExecuteEx(@ExecInfo) then
    begin
      WaitForSingleObject(ExecInfo.hProcess, INFINITE);
      GetExitCodeProcess(ExecInfo.hProcess, ExitCode);
      CloseHandle(ExecInfo.hProcess);

      Result.Success := (ExitCode = 0);
      if Result.Success then
      begin
        // Yeni oluþturulan .srt dosyalarýný topla
        if FindFirst(SubtitlesPath + '\*.srt', faAnyFile, SearchRec) = 0 then
        begin
          repeat
            Result.FileNames.Add(SearchRec.Name);
          until FindNext(SearchRec) <> 0;
          System.SysUtils.FindClose(SearchRec);
        end;

        Result.Message := 'Subtitle(s) downloaded successfully.';
      end
      else
        Result.Message := 'An error occurred while downloading the subtitle.';
    end
    else
    begin
      Result.Success := False;
      Result.Message := SysErrorMessage(GetLastError);
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.Message := E.Message;
    end;
  end;
end;

procedure OpenDownloadsFolder;
var
  DownloadsFolder: string;
begin
  // Downloads klasörünün yolunu belirleyin (uygulamanýn bulunduðu dizinin altýndaki Downloads klasörü)
  DownloadsFolder := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))
    + 'Downloads\Subtitles\';
  // Downloads klasörünü açma
  ShellExecute(0, 'open', PChar(DownloadsFolder), nil, nil, SW_SHOW);
end;

procedure TForm1.BitBtn1Click(Sender: TObject);
begin
    OpenDownloadsFolder;
end;

procedure TForm1.btnDownloadClick(Sender: TObject);
var
  Languages: array of string;
  i: Integer;
  Result: TDownloadResult;
  SubtitlesPath, SearchPattern: string;
  SR: TSearchRec;
  SubtitleFile, OutputFile: string;
begin
  if validateYoutubeUrl(txtYoutubeUrl.Text) then
  begin
    SetLength(Languages, mmLang.Lines.Count);
    for i := 0 to mmLang.Lines.Count - 1 do
      Languages[i] := Trim(mmLang.Lines[i]);

    Result := DownloadSubtitle(txtYoutubeUrl.Text, Languages);
    ShowMessage(Result.Message);

    if Result.Success and chkforChatbot.Checked then
    begin
      SubtitlesPath := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Downloads\Subtitles\';
      SearchPattern := SubtitlesPath + '*.srt';

      if FindFirst(SearchPattern, faAnyFile, SR) = 0 then
      begin
        repeat
          SubtitleFile := SubtitlesPath + SR.Name;
          OutputFile := ChangeFileExt(SubtitleFile, '.txt');
          CleanSubtitleFile_FormatSentences(SubtitleFile, OutputFile);
        until FindNext(SR) <> 0;
        FindClose(SR);
      end;
    end;

    OpenDownloadsFolder;
  end
  else
    ShowMessage('Incorrect YouTube URL format.');
  end;
end.

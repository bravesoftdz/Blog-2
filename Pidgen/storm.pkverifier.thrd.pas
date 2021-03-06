{*************************************************************************
* Copyright (C) 2010 stOrM! - All Rights Reserved                       *
*                                                                       *
* This file is part of pkverifier.                                      *
* tested on Windows 7 64Bit SP1                                         *
*                                                                       *
* This Source Code Form is subject to the terms of the Mozilla Public   *
* License, v. 2.0. If a copy of the MPL was not distributed with this   *
* file, You can obtain one at https://mozilla.org/MPL/2.0/.             *
*                                                                       *
*************************************************************************}

unit storm.pkverifier.thrd;

interface

uses
  System.SysUtils,
  WinApi.Windows,
  WinApi.ShlObj,
  WinApi.SHFolder,
  System.Win.Registry,
  System.Types,
  System.IOUtils,
  System.Classes,
  System.Threading,
  Generics.Collections;

type
  TDigitalPidId4 = packed record
    cbSize: DWORD;
    Unknown1: DWORD;
    ExtendedPid: array [0 .. 63] of Char;
    Activationid: array [0 .. 71] of Char;
    Edition: array [0 .. 63] of Char;
    Unknown3: array [0 .. 399] of Byte;
    Unknown2: array [0 .. 79] of Byte;
    EditionId: array [0 .. 63] of Char;
    LicenseType: array [0 .. 63] of Char;
    LicenseChannel: array [0 .. 63] of Char;
  end;

  TDigitalPidId = packed record
    cbSize: DWORD;
    Unknown: array [0 .. 27] of Byte;
    CryptoID: DWORD;
    Unknown2: array [0 .. 127] of Byte;
  end;

  TGeneratedPid = packed record
    case Byte of
      0:
        (cbSize: DWORD);
      1:
        (Pid: array [0 .. 24] of Char);
  end;

  TKeyValidationEvent = procedure(Sender: TObject) of object;
  TKeyValidationDoneEvent = procedure(Sender: TObject) of object;
  TKeyValidationErrorEvent = procedure(Sender: TObject;
    const AMessageStr: string) of object;

  TGenuineInfo = class
    FGeneratedPid_PID: string;
    FDigitalPidId_CryptoID: string;
    FDigitalPidId4_Activationid: string;
    FDigitalPidId4_Edition: string;
    FDigitalPidId4_EditionId: string;
    FDigitalPidId4_ExtendedPid: string;
    FDigitalPidId4_LicenseType: string;
    FDigitalPidId4_LicenseChannel: string;
    FEncryptedKey: string;
  end;

  TPkVerifier = class
  private
    FMPCID: string;
    FPID: string;
    FPidgenXPath: string;
    FLicenceKey: string;
    FKeyIsValid: Boolean;

    FGenuine: TDictionary<String, TGenuineInfo>;
    FGenuineInfo: TGenuineInfo;

    FOnKeyValidation: TKeyValidationEvent;
    FOnKeyValidationDone: TKeyValidationDoneEvent;
    FOnKeyValidationStatus: TKeyValidationErrorEvent;
  protected
    function GetMPCID: string;
    procedure SetMPCID(const AValue: string);
    function GetPID: string;
    procedure SetPID(const AValue: string);
    function GetPidgenXPath: string;
    procedure SetPidgenXPath(const AValue: string);
    function GetLicenceKey: string;
    procedure SetLicenceKey(const AValue: string);
    function getKeyIsValid: Boolean;
    procedure setKeyIsValid(const AValue: Boolean);
    procedure GetProcedureAddress(var P: Pointer;
      const ModuleName, ProcName: AnsiString); overload;
    procedure GetProcedureAddress(var P: Pointer; const ModuleName: AnsiString;
      dwIndex: Integer); overload;
    procedure LoadPidGenX(const dllPath: string);
    function SecureZeroMemory(ptr: PVOID; cnt: SIZE_T): Pointer;
    function GetSpecialFolder(CSIDL: Integer;
      ForceFolder: Boolean = FALSE): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Verify(const APath, AProductKey, Apkeyconfig, AMCPID: string;
      AAsynch: Boolean);
    function DecodeProductKey(const HexSrc: array of Byte): string;
    property MPCID: string read GetMPCID write SetMPCID;
    property Pid: string read GetPID write SetPID;
    property LicenceKey: string read GetLicenceKey write SetLicenceKey;
    property PidgenXPath: string read GetPidgenXPath write SetPidgenXPath;
    property KeyIsValid: Boolean read getKeyIsValid write setKeyIsValid;

    property Genuine: TDictionary<String, TGenuineInfo> read FGenuine
      write FGenuine;
    property GenuineInfo: TGenuineInfo read FGenuineInfo write FGenuineInfo;

    property OnKeyValidation: TKeyValidationEvent read FOnKeyValidation
      write FOnKeyValidation;
    property OnKeyValidationDone: TKeyValidationDoneEvent
      read FOnKeyValidationDone write FOnKeyValidationDone;
    property OnKeyValidationError: TKeyValidationErrorEvent
      read FOnKeyValidationStatus write FOnKeyValidationStatus;
  end;

implementation

{ TPkVerifier }

var
  _PidGenX:

    function(WindowsKey, PkeyPath, MPCID: PWideChar; UnknownUsage: Integer;
    var GeneratedProductID: TGeneratedPid;
    var OldDigitalProductID: TDigitalPidId;
    var DigitalProductID: TDigitalPidId4): HRESULT; stdcall;

constructor TPkVerifier.Create;
begin
  inherited;
  FMPCID := '';
  FPidgenXPath := '';
  FLicenceKey := '';
  FKeyIsValid := FALSE;

  FGenuine := TDictionary<String, TGenuineInfo>.Create;
  FGenuineInfo := TGenuineInfo.Create;
end;

destructor TPkVerifier.Destroy;
begin
  FreeAndNil(FGenuineInfo);
  FreeAndNil(FGenuine);

  inherited;
end;

function TPkVerifier.getKeyIsValid: Boolean;
begin
  result := FKeyIsValid;
end;

function ByteToHex(InByte: Byte): string;
const
  Digits: array [0 .. 15] of Char = '0123456789ABCDEF';
begin
  result := Digits[InByte shr 4] + Digits[InByte and $0F];
end;

function TPkVerifier.GetLicenceKey: string;
var
  Reg: TRegistry;
  binarySize: Integer;
  HexBuf: array of Byte;
begin
  Reg := TRegistry.Create(KEY_READ OR KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\SOFTWARE\Microsoft\Windows NT\CurrentVersion') then
    begin
      binarySize := Reg.GetDataSize('DigitalProductId');
      SetLength(HexBuf, binarySize);
      if binarySize > 0 then
      begin
        Reg.ReadBinaryData('DigitalProductId', HexBuf[0], binarySize);
      end;
      Reg.CloseKey;
    end;
  finally
    FreeAndNil(Reg);
    result := DecodeProductKey(HexBuf);
  end;
end;

function GetLicAsHex: string;
var
  Reg: TRegistry;
  binarySize: Integer;
  HexBuf: array of Byte;
  i: Integer;
begin
  Reg := TRegistry.Create(KEY_READ OR KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\SOFTWARE\Microsoft\Windows NT\CurrentVersion') then
    begin
      binarySize := Reg.GetDataSize('DigitalProductId');
      SetLength(HexBuf, binarySize);
      if binarySize > 0 then
      begin
        Reg.ReadBinaryData('DigitalProductId', HexBuf[0], binarySize);
      end;
      Reg.CloseKey;
    end;
  finally
    FreeAndNil(Reg);
    for i := Low(HexBuf) to High(HexBuf) do
    begin
      result := result + ' ' + ByteToHex(HexBuf[i]);
    end;
  end;
end;

function TPkVerifier.GetMPCID: string;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ OR KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\SOFTWARE\Microsoft\Windows NT\CurrentVersion') then
    begin
      result := Reg.ReadString('ProductID');
      result := copy(result, 1, 5);
      Reg.CloseKey;
    end;
  finally
    FreeAndNil(Reg);
  end;
end;

procedure TPkVerifier.GetProcedureAddress(var P: Pointer;
  const ModuleName, ProcName: AnsiString);
var
  ModuleHandle: HMODULE;
begin
  if not Assigned(P) then
  begin
    ModuleHandle := GetModuleHandleA(PAnsiChar(AnsiString(ModuleName)));
    if ModuleHandle = 0 then
    begin
      ModuleHandle := LoadLibraryA(PAnsiChar(ModuleName));
      if ModuleHandle = 0 then
        raise Exception.CreateFmt('Library %s not found.', [ModuleName]);
    end;
    P := Pointer(GetProcAddress(ModuleHandle, PAnsiChar(ProcName)));
    if not Assigned(P) then
      raise Exception.CreateFmt('Procedure not found %s in %s (%s)',
        [ModuleName, ProcName, SysErrorMessage(GetLastError)]);
  end;
end;

function TPkVerifier.GetPID: string;
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_READ OR KEY_WOW64_64KEY);
  try
    Reg.RootKey := HKEY_LOCAL_MACHINE;
    if Reg.OpenKeyReadOnly('\SOFTWARE\Microsoft\Windows NT\CurrentVersion') then
    begin
      result := Reg.ReadString('ProductID');
      Reg.CloseKey;
    end;
  finally
    FreeAndNil(Reg);
  end;
end;

function TPkVerifier.GetPidgenXPath: string;
begin
  result := GetSpecialFolder(CSIDL_SYSTEM);
end;

procedure TPkVerifier.GetProcedureAddress(var P: Pointer;
  const ModuleName: AnsiString; dwIndex: Integer);
var
  ModuleHandle: HMODULE;
begin
  if not Assigned(P) then
  begin
    ModuleHandle := GetModuleHandleA(PAnsiChar(AnsiString(ModuleName)));
    if ModuleHandle = 0 then
    begin
      ModuleHandle := LoadLibraryA(PAnsiChar(ModuleName));
      if ModuleHandle = 0 then
        raise Exception.CreateFmt('Library %s not found.', [ModuleName]);
    end;
    P := Pointer(GetProcAddress(ModuleHandle, MakeIntResource(dwIndex)));
    if not Assigned(P) then
      raise Exception.CreateFmt('Procedure not found %s in %d (%s)',
        [ModuleName, dwIndex, SysErrorMessage(GetLastError)]);
  end;
end;

function TPkVerifier.GetSpecialFolder(CSIDL: Integer;
  ForceFolder: Boolean): string;
var
  i: Integer;
begin
  SetLength(result, MAX_PATH);
  if ForceFolder then
    ShGetFolderPath(0, CSIDL OR CSIDL_FLAG_CREATE, 0, 0, PChar(result))
  else
    ShGetFolderPath(0, CSIDL, 0, 0, PChar(result));
  i := Pos(#0, result);
  if i > 0 then
    SetLength(result, pred(i));

  result := IncludeTrailingPathDelimiter(result);
end;

procedure TPkVerifier.LoadPidGenX(const dllPath: string);
begin
  GetProcedureAddress(@_PidGenX, AnsiString(dllPath), 118);
end;

function TPkVerifier.SecureZeroMemory(ptr: PVOID; cnt: SIZE_T): Pointer;
begin
  FillChar(ptr^, cnt, 0);
  result := ptr;
end;

procedure TPkVerifier.setKeyIsValid(const AValue: Boolean);
begin
  FKeyIsValid := AValue;
end;

procedure TPkVerifier.SetLicenceKey(const AValue: string);
begin
  if Length(AValue) > 0 then
    FLicenceKey := AValue;
end;

procedure TPkVerifier.SetMPCID(const AValue: string);
begin
  if Length(AValue) > 0 then
    FMPCID := AValue;
end;

procedure TPkVerifier.SetPID(const AValue: string);
begin
  if Length(AValue) > 0 then
    FPID := AValue;
end;

procedure TPkVerifier.SetPidgenXPath(const AValue: string);
begin
  if Length(AValue) > 0 then
    FPidgenXPath := AValue;
end;

procedure TPkVerifier.Verify(const APath, AProductKey, Apkeyconfig,
  AMCPID: string; AAsynch: Boolean);
var
  GenPID: TGeneratedPid;
  DigitialPid: TDigitalPidId;
  DigitalPid4: TDigitalPidId4;
  hr: HRESULT;
begin
  SecureZeroMemory(@GenPID, SizeOf(GenPID));
  GenPID.cbSize := SizeOf(GenPID);

  SecureZeroMemory(@DigitialPid, SizeOf(DigitialPid));
  DigitialPid.cbSize := SizeOf(DigitialPid);

  SecureZeroMemory(@DigitalPid4, SizeOf(DigitalPid4));
  DigitalPid4.cbSize := SizeOf(DigitalPid4);

  LoadPidGenX(APath + 'pidgenx.dll');

  case AAsynch of
    true:
      begin
        TTask.Run(
          procedure
          begin
            TThread.Queue(nil,
              Procedure
              begin
                if Assigned(FOnKeyValidation) then
                  FOnKeyValidation(self);
              end);
            try
              hr := _PidGenX(PWideChar(AProductKey), PWideChar(Apkeyconfig),
                PWideChar(AMCPID), 0, GenPID, DigitialPid, DigitalPid4);
            finally

              if Succeeded(hr) then
              begin
                FKeyIsValid := true;

                TThread.Queue(nil,
                  Procedure
                  begin

                      if Assigned(FOnKeyValidationDone) then
                        FOnKeyValidationDone(self);

                      if Assigned(FOnKeyValidationStatus) then
                        FOnKeyValidationStatus(self,
                          Format('%s is genuine: %s',
                          [AProductKey, Lowercase(BoolToStr(FKeyIsValid, true))]));
                  end);

                SecureZeroMemory(@GenPID, SizeOf(GenPID));
                SecureZeroMemory(@DigitialPid, SizeOf(DigitialPid));
                SecureZeroMemory(@DigitalPid4, SizeOf(DigitalPid4));

              end
              else if not(Succeeded(hr)) then
              begin
                FKeyIsValid := FALSE;

                TThread.Queue(nil,
                  Procedure
                  begin
                    if Assigned(FOnKeyValidationDone) then
                      FOnKeyValidationDone(self);

                    if Assigned(FOnKeyValidationStatus) then
                      FOnKeyValidationStatus(self,
                        Format('%s is genuine: %s',
                        [AProductKey, lowercase(BoolToStr(FKeyIsValid, true))]));
                  end);

                SecureZeroMemory(@GenPID, SizeOf(GenPID));
                SecureZeroMemory(@DigitialPid, SizeOf(DigitialPid));
                SecureZeroMemory(@DigitalPid4, SizeOf(DigitalPid4));
              end;
            end;
          end);
      end;
    false:
      begin
        if Assigned(FOnKeyValidation) then
          FOnKeyValidation(self);

        hr := _PidGenX(PWideChar(AProductKey), PWideChar(Apkeyconfig),
          PWideChar(AMCPID), 0, GenPID, DigitialPid, DigitalPid4);

        if Succeeded(hr) then
        begin
          FKeyIsValid := true;

          if Assigned(FOnKeyValidationDone) then
            FOnKeyValidationDone(self);

          if Assigned(FOnKeyValidationStatus) then
            FOnKeyValidationStatus(self, Format('%s is genuine: %s',
              [AProductKey, Lowercase(BoolToStr(FKeyIsValid, true))]));

          // let's display some additional information for our licence
          FGenuineInfo.FGeneratedPid_PID := GenPID.Pid;
          FGenuineInfo.FDigitalPidId_CryptoID := DigitialPid.CryptoID.ToString;
          FGenuineInfo.FDigitalPidId4_Activationid := DigitalPid4.Activationid;
          FGenuineInfo.FDigitalPidId4_Edition := DigitalPid4.Edition;
          FGenuineInfo.FDigitalPidId4_EditionId := DigitalPid4.EditionId;
          FGenuineInfo.FDigitalPidId4_ExtendedPid := DigitalPid4.ExtendedPid;
          FGenuineInfo.FDigitalPidId4_LicenseType := DigitalPid4.LicenseType;
          FGenuineInfo.FDigitalPidId4_LicenseChannel :=
            DigitalPid4.LicenseChannel;
          FGenuineInfo.FEncryptedKey := GetLicAsHex;
          FGenuine.Add('storm', FGenuineInfo);

          SecureZeroMemory(@GenPID, SizeOf(GenPID));
          SecureZeroMemory(@DigitialPid, SizeOf(DigitialPid));
          SecureZeroMemory(@DigitalPid4, SizeOf(DigitalPid4));
        end
        else if not(Succeeded(hr)) then
        begin
          FKeyIsValid := FALSE;

          if Assigned(FOnKeyValidationDone) then
            FOnKeyValidationDone(self);

          if Assigned(FOnKeyValidationStatus) then
            FOnKeyValidationStatus(self, Format('%s is genuine: %s',
              [AProductKey, Lowercase(BoolToStr(FKeyIsValid, true))]));
        end;
      end;
  end;
end;

function TPkVerifier.DecodeProductKey(const HexSrc: array of Byte): string;
const
  StartOffset: Integer = $34;
  EndOffset: Integer = $34 + 15;
  Digits: array [0 .. 23] of Char = ('B', 'C', 'D', 'F', 'G', 'H', 'J', 'K',
    'M', 'P', 'Q', 'R', 'T', 'V', 'W', 'X', 'Y', '2', '3', '4', '6', '7',
    '8', '9');
  dLen: Integer = 29;
  sLen: Integer = 15;
var
  HexDigitalPID: array of CARDINAL;
  Des: array of Char;
  i, N: Integer;
  HN, Value: CARDINAL;
begin
  result := '';
  SetLength(HexDigitalPID, dLen);
  for i := StartOffset to EndOffset do
  begin
    HexDigitalPID[i - StartOffset] := HexSrc[i];
  end;

  SetLength(Des, dLen + 1);

  for i := dLen - 1 downto 0 do
  begin
    if (((i + 1) mod 6) = 0) then
    begin
      Des[i] := '-';
    end
    else
    begin
      HN := 0;
      for N := sLen - 1 downto 0 do
      begin
        Value := (HN shl 8) or HexDigitalPID[N];
        HexDigitalPID[N] := Value div 24;
        HN := Value mod 24;
      end;
      Des[i] := Digits[HN];
    end;
  end;
  Des[dLen] := Chr(0);

  for i := 0 to Length(Des) do
  begin
{$R-}
    result := result + Des[i];
{$R+}
  end;
end;

end.

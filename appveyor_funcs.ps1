$nl = "`r`n"
$wc = New-Object 'System.Net.WebClient'

function zip2nuget($file, $id)
{
  $tmp = 'C:\nutmp';
  $here = get-location;
  
  if(Test-Path $tmp) {
    Remove-Item $tmp -Force -Recurse;
  }
  
  iex "7z x -o$tmp $file";
  cd $tmp;
  iex "nuget spec $id";
  (Get-Content "$id.nuspec") -join "`n" -replace "(?s)<licenseUrl>.*</dependencies>", "<description>$id</description>" | Out-File "$id.nuspec";
  iex "nuget pack $id.nuspec -version $($env:APPVEYOR_BUILD_VERSION)";
  copy "*.nupkg" $here;
  cd $here;
}

function Print-File($txt)
{
  Get-Content $txt | ForEach-Object {
    echo "$_"
  }
}

function Invoke($exe, $al, $output=0)
{
  echo "$nl> INVOKE $exe $al <$nl$nl";
  if($al) {
    Measure-Command {
      $process = (start-process $exe $al -Wait -NoNewWindow -RedirectStandardOutput C:\out.txt -RedirectStandardError C:\err.txt);
    }
  }
  else {
    Measure-Command {
      $process = (start-process $exe -Wait -NoNewWindow -RedirectStandardOutput C:\out.txt -RedirectStandardError C:\err.txt);
    }
  }
  
  if($output) {
    echo "stdout:"; print-file 'C:\out.txt';
    echo "stderr:"; print-file 'C:\err.txt';
  }
  return $process.ExitCode;
}

# warning: ugly
function Push-Ctest-Results($dir, $prefix='')
{
  $head = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n<assembly name=`"`" run-date=`"1970-01-01`" run-time=`"00:00:00`" configFile=`"`" time=`"0`" total=`"0`" passed=`"0`" failed=`"0`" skipped=`"0`" environment=`"`">`n<class time=`"0`" name=`"`" total=`"0`" passed=`"0`" failed=`"0`" skipped=`"0`">`n";
  $foot = "</class>`n</assembly>`n";
  $out = Select-String '(?s)\d+\/\d+ Testing.*?end time.*?[-]{58}' -input ((Get-Content $dir\Testing\Temporary\LastTest.log) -join "`n") -AllMatches;
  $xml = $head;
  $num = 0;
  
  Select-String '(\w+)\s+(\d+)\s+(\d+(\.\d{1,3})?)' -input (Get-Content $dir\Testing\Temporary\CTestCostData.txt)-AllMatches | % {$_.Matches} | % {
    $name = $prefix + $_.Groups[1].Value;
    $res = @{$true="Pass";$false="Fail"}[$_.Groups[2].Value -eq 1];
    $time = $_.Groups[3].Value;
    $output = $out.Matches[$num].Value -replace "$([char]8)", "";
    
    $maxlen = 5000;
    if($output.length -gt $maxlen) {$output = $output.substring(0,$maxlen) + "`n`n*snip*"};
    if($time -eq '0') {$time = '0.000'};
    
    $output = [Security.SecurityElement]::Escape($output);
    $num++;
    $xml += "<test name=`"$name`" type=`"`" method=`"`" result=`"$res`" time=`"$time`">`n<output>$output</output>`n</test>`n"
  };
  
  $xml += $foot;
  $xml > ".\xunit_tmp.xml";
  $wc.UploadFile("https://ci.appveyor.com/api/testresults/xunit/$($env:APPVEYOR_JOB_ID)", (Resolve-Path .\xunit_tmp.xml));
}

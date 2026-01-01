set -l pager_flag
if contains -- --one-page $argv
    set pager_flag 1
    set argv (string match -v -- --one-page $argv)
end
/bin/cat /etc/passwd | python3 -c 'import sys,argparse;p=argparse.ArgumentParser(description="List users from /etc/passwd in a table");p.add_argument("-f","--filter",default="",help="filter rows containing string");p.add_argument("-s","--sort",type=int,choices=range(1,8),metavar="1-7",default=None,help="sort by column: 1=user 2=pw 3=uid 4=gid 5=gecos 6=home 7=shell");a=p.parse_args(sys.argv[1:]);ls=[l for l in sys.stdin.read().split("\n") if l and not l.startswith("#") and len(l.split(":"))==7 and a.filter in l];headers=("user","pw","uid","gid","gecos","home","shell");xs=[dict(zip(headers,l.split(":"))) for l in ls];xs=sorted(xs,key=lambda x:int(x[headers[a.sort-1]]) if a.sort in (3,4) else x[headers[a.sort-1]]) if a.sort else xs;widths={h:max(len(h),max((len(x[h]) for x in xs),default=0)) for h in headers};colors=["\033[31m","\033[32m","\033[33m","\033[34m","\033[35m","\033[36m","\033[37m"];B="\033[34m";R="\033[0m";align=lambda h:">" if h in ("uid","gid") else "<";print(f"{B}┌"+"┬".join("─"*(widths[h]+2) for h in headers)+f"┐{R}");print(f"{B}│{R}"+f"{B}│{R}".join(f" {h.upper():{align(h)}{widths[h]}} " for h in headers)+f"{B}│{R}");print(f"{B}├"+"┼".join("─"*(widths[h]+2) for h in headers)+f"┤{R}");[print(f"{B}│{R}"+f"{B}│{R}".join(f"{colors[i]} {x[h]:{align(h)}{widths[h]}} {R}" for i,h in enumerate(headers))+f"{B}│{R}") for x in xs];print(f"{B}└"+"┴".join("─"*(widths[h]+2) for h in headers)+f"┘{R}")' $argv | if test -n "$pager_flag"
    less -R
else cat
end

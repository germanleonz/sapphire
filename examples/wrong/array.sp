Record Int as
  val :: Float
end

Int [10] [20] arreglo
Bool[10]     barreglo
Char[2][30]  carreglo

print arreglo, barreglo, carreglo

Record Thing as
      ident :: String
    , coord :: Int[2]
end

def func :: Int, Bool -> Int
imp func (a,b) as
  if b then
    return a * 2
  else
    return a - 2
  end
end

Thing[10] arr
# Thing n
# n.ident = "n"
# print n

Int[10][2] a
Int[10+20] f
Int["hola"] f

a[a[1][3]][3 + 2 * arr[1].coord[0]] = 2.0
a["hola"] = 10
arr[1].coord[0] = a[func(3,true)][func(3,false)]

arr[3].coord[0] = 1
arr[3].ident = "crash-site"
arr[3].ident[1] = "error"
arr[3] = "error"

Int d,g,hh
read d

g = 2 + d
if true then
  hh = g * 2
else
  hh = 2
end

g = 1

Int bbb = 1
read bbb
Int[bbb+ 2] dd      # it doesn't get defined
dd[d] = 2

print dd[2]

read arr

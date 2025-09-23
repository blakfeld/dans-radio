# Test file with intentional RuboCop violations
class TestClass
  def test_method( param1,param2 )
    hash = { :key1=>'value1',:key2=>'value2' }
    array = [ 1,2,3,4,5 ]
    
    if param1==true
      puts"Hello"
    else
      puts"World"
    end
    
    return hash
  end
  
  def another_method
    x=1+2
    y=x*3
    return y
  end
end

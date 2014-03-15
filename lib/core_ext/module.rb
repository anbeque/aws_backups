class Module
  def attr_accessor_bool(*names)
    names.each do |name|
      inst_variable_name = "@#{name}".to_sym
      define_method "#{name}" do
        instance_variable_get inst_variable_name
      end
      define_method "#{name}=" do |value|
        instance_variable_set inst_variable_name, value.to_bool
      end
    end
  end
  def attr_accessor_i(*names)
    names.each do |name|
      inst_variable_name = "@#{name}".to_sym
      define_method "#{name}" do
        instance_variable_get inst_variable_name
      end
      define_method "#{name}=" do |value|
        instance_variable_set inst_variable_name, value.to_i
      end
    end
  end
end

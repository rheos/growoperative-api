
[1mFrom:[0m /home/dijientt/proj/rheos/railsbackend/spec/rails_helper.rb @ line 40 :

    [1;34m35[0m:     [1;34;4mRails[0m.application.load_seed
    [1;34m36[0m:   [32mend[0m
    [1;34m37[0m: 
    [1;34m38[0m:   config.before([33m:each[0m) [32mdo[0m |test|
    [1;34m39[0m:     binding.pry
 => [1;34m40[0m:     [32munless[0m test.metadata[[33m:skip_hooks[0m]
    [1;34m41[0m:       [1;34;4mDatabaseCleaner[0m.strategy = [33m:deletion[0m
    [1;34m42[0m:       [1;34;4mDatabaseCleaner[0m.clean_with([33m:truncation[0m)
    [1;34m43[0m:       [1;34;4mRails[0m.application.load_seed
    [1;34m44[0m:     [32mend[0m
    [1;34m45[0m:   [32mend[0m


Your API Password is: 4368f9a8e47c782e7a1fad1c5a8344561389cd4e02448bdbe634ccb62bcbec94

http://articles.slicehost.com/2008/5/13/slicemanager-api-documentation

https://4368f9a8e47c782e7a1fad1c5a8344561389cd4e02448bdbe634ccb62bcbec94@api.slicehost.com/slices/

flavors:
    id 1 is 256 megs

images:
    id 11 is ubuntu 8.10
    

in rest-client:
    >> post "slices", :slice => {:image_id => 2, :flavor_id => 1, :name => "DJ3"}

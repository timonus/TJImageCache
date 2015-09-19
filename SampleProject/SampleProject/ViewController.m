//
//  ViewController.m
//  SampleProject
//
//  Created by Tim Johnsen on 9/19/15.
//  Copyright © 2015 tijo. All rights reserved.
//

#import "ViewController.h"
#import "TJImageView.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = self.tableView.bounds.size.width;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 100;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *const kCellIdentifier = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
    static const NSInteger kCellImageViewTag = 101;
    TJImageView *imageView = (TJImageView *)[cell.contentView viewWithTag:kCellImageViewTag];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellIdentifier];
        imageView = [[TJImageView alloc] initWithFrame:cell.contentView.bounds];
        imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        imageView.tag = kCellImageViewTag;
        [cell.contentView addSubview:imageView];
    }
    
    const CGFloat size = cell.bounds.size.width;
    imageView.imageURLString = [NSString stringWithFormat:@"http://lorempixel.com/%0.0f/%0.0f/animals/%ld", size, size, (long)indexPath.row];
    
    return cell;
}

@end
